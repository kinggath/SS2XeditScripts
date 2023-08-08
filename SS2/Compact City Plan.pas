{
    SS2_SLCP_CityPlan_13_SS2GraygardenBasics "[SS2] Graygarden Basics" [MISC:020471D3]
}
unit CompactCityPlan;

    uses 'SS2\SS2Lib';
    uses 'SS2\CobbLibrary';

    const
        // Blacklist, editor IDs in the blacklist will never be SCOLed, no matter what.
        edidListFileName_Blacklist  = 'CompactCityPlan.Blacklist.txt';

        // Whitelists. Blacklist has priority over them.
        edidListFileName_Clutter    = 'cache_kgSIM_CPSCOLWhitelist_Clutter.txt';
        edidListFileName_Other      = 'cache_kgSIM_CPSCOLWhitelist_Other.txt';
        edidListFileName_Structure  = 'cache_kgSIM_CPSCOLWhitelist_Structure.txt';

        // Structure SCOLs = 6, Other SCOLs = 7, and Clutter SCOLs = 8
        STATIC_TYPE_NONE = 0;
        STATIC_TYPE_CLUTTER = 8;
        STATIC_TYPE_OTHER = 7;
        STATIC_TYPE_STRUCTURE = 6;

    var
        kgSIM_CPSCOLWhitelist_Clutter: IInterface;
        kgSIM_CPSCOLWhitelist_Other: IInterface;
        kgSIM_CPSCOLWhitelist_Structure: IInterface;
        scolBlacklist: IInterface;

        kgSIM_FarHarborRequired: IInterface;
        kgSIM_NukaWorldRequired: IInterface;
        pivotDummy: IInterface;

        simSettMaster: IInterface;

        curLayerJson: TJsonObject;

        entriesLookupList: TList;
        entriesToDelete: TStringList;
        entriesToPrepend: TList;

        targetFile: IInterface;

        formCache_Clutter: TStringList;
        formCache_Other: TStringList;
        formCache_Structure: TStringList;

        //currentPrependIndex: integer;
        simSettFileAge: integer;

        hasFarHarbor: boolean;
        hasNukaWorld: boolean;

        checkScolUsage: boolean;
        ignoreNavmeshed: boolean;
        ignoreColorRemap: boolean;
        useBlacklist: boolean;

        powerGridMapping: TJsonObject;
        powerConnectionData: TJsonObject;
        currentLayoutIndexOffset: Integer;
        {
            key:
                oldIndex
                    somehow figure out for each when processing it?
            value:
                newIndex
                    initially := oldIndex
                    update when:
                        - deletion: is set to -1
                        - swap: need both oldIndices (use their newIndex)
                        - append: generate new
        }

    {registerEntryForDeletion(structIndex);
                            entriesToDelete.add(IntToStr(structIndex));}
{
}
    procedure registerEntryForDeletion(itemIndex: Integer);
    var
        curData: TJsonObject;
    begin
        // AddMessage('Registering deletion: '+IntToStr(itemIndex));

        entriesToDelete.add(IntToStr(itemIndex));
    end;

    function getIndexForItem(item: IInterface): integer;
    var
        i: integer;
    begin
        Result := -1;

        for i:=0 to entriesLookupList.count-1 do begin
            if(Equals(ObjectToElement(entriesLookupList[i]), item)) then begin
                Result := i;
                exit;
            end;
        end;

        Result := entriesLookupList.add(TObject(item));
    end;

    procedure setNewPowerConnectionByIndex(itemIndex, newVal: Integer);
    var
        curData: TJsonObject;
    begin
        curData := powerConnectionData.O[IntToStr(itemIndex)];

        curData.I['newIndex'] := newVal;
    end;

    procedure setNewPowerConnectionByItem(item: IInterface; newVal: Integer);
    var
        index: integer;
    begin
        index := getIndexForItem(item);
        if(index > -1) then begin
            setNewPowerConnectionByIndex(index, newVal);
        end;
    end;

    function getNewPowerConnectionByIndex(itemIndex: Integer): Integer;
    var
        curData: TJsonObject;
    begin
        Result := -2;
        curData := powerConnectionData.O[IntToStr(itemIndex)];

        if(curData.count > 0) then begin
            Result := curData.I['newIndex'];
            exit;
        end;
    end;

    function getNewPowerConnectionByItem(item: IInterface): Integer;
    var
        index : integer;
    begin
        index := getIndexForItem(item);
        if(index > -1) then begin
            Result := getNewPowerConnectionByIndex(index);
        end;
    end;


    function isMasterAllowed(fileName: string): boolean;
    begin
        if(SameText(fileName, GetFileName(targetFile))) then begin
            Result := true;
            exit;
        end;
        Result := HasMaster(targetFile, fileName);
    end;

    function isUsedInSCOL(e: IInterface): boolean;
    var
        numRefs, i: integer;
        curRec, navmesh: IInterface;
        edid: string;
    begin
        Result := false;


        // disabled?
        if(not checkScolUsage) then begin
            exit;
        end;
        edid := EditorID(e);

        AddMessage('Checking SCOL usage of '+edid);

        // check navmesh
        if(ignoreNavmeshed) then begin
            navmesh := ElementBySignature(e, 'NVNM');
            if(assigned(navmesh)) then begin
                AddMessage('Object is navmeshed, skipping');
                scolBlacklist.add(edid);
                Result := STATIC_TYPE_NONE;
                exit;
            end;
        end;

        if(ignoreColorRemap) then begin
             navmesh := ElementByPath(e, 'Model\MODC - Color Remapping Index');
             if(assigned(navmesh)) then begin
                AddMessage('Object has remapping index, skipping');

                scolBlacklist.add(edid);
                Result := STATIC_TYPE_NONE;
                exit;
            end;
        end;

        numRefs := ReferencedByCount(e)-1;
        for i := 0 to numRefs do begin
            curRec := ReferencedByIndex(e, i);
            if (Signature(curRec) = 'SCOL') then begin
                Result := true;
                exit;
            end;
        end;

        // AddMessage('SCOL usage of '+EditorID(e)+'? '+BoolToStr(Result));
    end;

    function checkIndirectDependency(e: IInterface): boolean;
    begin
        Result := true;
        if(not FilesEqual(GetFile(e), simSettMaster)) then begin
            exit;
        end;
        if(not hasFarHarbor) then begin
            if(isReferencedBy(e, hasFarHarbor)) then begin
                Result := false;
                exit;
            end;
        end;

        if(not hasNukaWorld) then begin
            if(isReferencedBy(e, hasNukaWorld)) then begin
                Result := false;
                exit;
            end;
        end;
    end;


    function getStaticType(stat: IINterface): integer;
    var
        edid: string;
        navmesh: IInterface;
    begin

        edid := EditorID(stat);

        if(scolBlacklist.indexOf(edid) > -1) then begin
            // blacklisted
            Result := STATIC_TYPE_NONE;
            exit;
        end;

        if(formCache_Structure.indexOf(edid) > -1) then begin
            Result := STATIC_TYPE_STRUCTURE;
            exit;
        end;

        if(formCache_Clutter.indexOf(edid) > -1) then begin
            Result := STATIC_TYPE_CLUTTER;
            exit;
        end;

        if(formCache_Other.indexOf(edid) > -1) then begin
            Result := STATIC_TYPE_OTHER;
            exit;
        end;


        if(isUsedInSCOL(stat)) then begin
            formCache_Other.add(edid);
            Result := STATIC_TYPE_OTHER;
            exit;
        end;


        // put into blacklist for faster future lookup
        scolBlacklist.add(edid);

        Result := STATIC_TYPE_NONE;
    end;

    function processMergeScol(scolPos, scolRot: TJsonObject; scolScale: float; item, scolForm: IInterface; curScolBase: TJsonObject; lookupIndex: integer): boolean;
    var
        parts, curPart, placements, curPartBase,curPlacement: IInterface;
        formIdString, scaleString: string;
        partPosVector, partPosVectorScaled, partRotVector, rotatedData, vectorTotalPos, vectorMinPos, vectorMaxPos: TJsonObject;
        i,j: integer;
        partScale, posX, posY, posZ, rotX, rotY, rotZ, scale: float;
    begin
        AddMessage('Adding from SCOL: '+EditorID(scolForm));
        Result := false;
        parts := ElementByPath(scolForm, 'Parts');


        for i:=0 to ElementCount(parts)-1 do begin
            curPart := ElementByIndex(parts, i);

            curPartBase := pathLinksTo(curPart, 'ONAM');
            // AddMessage('CurPart: '+EditorID(curPartBase));
            if(GetLoadOrderFormID(curPartBase) = $00035812) then begin//StaticCollectionPivotDummy [STAT:00035812]
                //AddMessage('skipping PivotDummy');
                continue;
            end;
            formIdString := '$'+IntToHex(GetLoadOrderFormID(curPartBase), 8);

            placements := ElementByPath(curPart, 'DATA');
            for j:=0 to ElementCount(placements)-1 do begin
                Result := true;
                curPlacement := ElementByIndex(placements, j);

                partPosVector := getPositionVector(curPlacement, '');
                partPosVectorScaled := VectorMultiply(partPosVector, scolScale);
                partRotVector := getRotationVector(curPlacement, '');

                partScale := 1.0;
                scaleString := geev(curPlacement, 'Scale');
                if(scaleString <> '') then begin
                    // AddMessage('scaleString='+scaleString);
                    partScale := StrToFloat(scaleString);
                end;

                rotatedData := GetCoordinatesRelativeToBase(scolPos, scolRot, partPosVectorScaled, partRotVector);

                posX := rotatedData.O['pos'].F['x'];
                posY := rotatedData.O['pos'].F['y'];
                posZ := rotatedData.O['pos'].F['z'];
                rotX := rotatedData.O['rot'].F['x'];
                rotY := rotatedData.O['rot'].F['y'];
                rotZ := rotatedData.O['rot'].F['z'];
                scale:= scolScale*partScale;
                // AddMessage('scolScale*partScale=scale -> '+FloatToStr(scolScale)+'*'+FloatToStr(partScale)+'='+FloatToStr(scale));


                vectorTotalPos := curScolBase.O['sumPos'];
                vectorMinPos := curScolBase.O['minPos'];
                vectorMaxPos := curScolBase.O['maxPos'];


                vectorTotalPos.F['x'] := vectorTotalPos.F['x']+posX;
                vectorTotalPos.F['y'] := vectorTotalPos.F['y']+posY;
                vectorTotalPos.F['z'] := vectorTotalPos.F['z']+posZ;

                if(vectorMinPos.F['x'] > posX) then begin
                    vectorMinPos.F['x'] := posX;
                end;

                if(vectorMinPos.F['y'] > posY) then begin
                    vectorMinPos.F['y'] := posY;
                end;

                if(vectorMinPos.F['z'] > posZ) then begin
                    vectorMinPos.F['z'] := posZ;
                end;


                if(vectorMaxPos.F['x'] < posX) then begin
                    vectorMaxPos.F['x'] := posX;
                end;

                if(vectorMaxPos.F['y'] < posY) then begin
                    vectorMaxPos.F['y'] := posY;
                end;

                if(vectorMaxPos.F['z'] < posZ) then begin
                    vectorMaxPos.F['z'] := posZ;
                end;

                curScolBase.I['numPlacements'] := curScolBase.I['numPlacements']+1;

                curPlacement := curScolBase.O['contents'].A[formIdString].AddObject();

                curPlacement.F['posX'] := posX;
                curPlacement.F['posY'] := posY;
                curPlacement.F['posZ'] := posZ;

                curPlacement.F['rotX'] := rotX;
                curPlacement.F['rotY'] := rotY;
                curPlacement.F['rotZ'] := rotZ;

                curPlacement.F['scale'] := scale;
                        // curPlacement.I['type'] := staticType;

                if(i=0) and (j=0) then begin
                    //curPlacement.I['IInterface'] := entriesToDelete.add(TObject(item));
                    curPlacement.I['IInterface'] := lookupIndex + 1;
                    curScolBase.I['numOldRecords'] := curScolBase.I['numOldRecords']+1;
                    // setPowerConnectionData(powerIndex, powerType, -1);
                end;

                partPosVector.free();
                partPosVectorScaled.free();
                partRotVector.free();
                rotatedData.free();
            end;
        end;

        scolPos.free();
        scolRot.free();
    end;

    function AddNewRecordToGroup(const g: IInterface; const s: String): IInterface;
    begin
        Result := Add(g, s, True);
        if not Assigned(Result) then
            Result := Add(g, s, True); // tries twice because
    end;

    function createScol(name: string): IInterface;
    var
        scolGroup: IInterface;
    begin
        scolGroup := GroupBySignature(targetFile, 'SCOL');
        if(not assigned(scolGroup)) then begin
            scolGroup := Add(targetFile, 'SCOL', True);
        end;

        Result := AddNewRecordToGroup(scolGroup, 'SCOL - Static Collection');

        SetElementEditValues(Result, 'EDID', name);
    end;

    procedure swapStructs(s1, s2: IInterface);
    var
        i: integer;
        tempNames: TStringList;
        curProp: IInterface;
        curName: string;
        curProp1, curProp2: IInterface;
        tmpVal: variant;
    begin
        tempNames := TStringList.create;

        for i:=0 to ElementCount(s1)-1 do begin
            curProp := ElementByIndex(s1, i);
            curName := geevt(curProp, 'memberName');
            tempNames.add(curName);
        end;

        for i:=0 to ElementCount(s2)-1 do begin
            curProp := ElementByIndex(s2, i);
            curName := geevt(curProp, 'memberName');
            if(tempNames.indexOf(curName) < 0) then begin
                tempNames.add(curName);
            end;
        end;

        for i:=0 to tempNames.count-1 do begin
            curName := tempNames[i];
            curProp1 := getRawStructMember(s1, curName);
            curProp2 := getRawStructMember(s2, curName);


            if(assigned(curProp1) and assigned(curProp2)) then begin
                tmpVal := getValueAsVariant(curProp1, nil);

                setPropertyValue(curProp1, getValueAsVariant(curProp2, nil));
                setPropertyValue(curProp2, tmpVal);
            end else begin
                if(assigned(curProp1)) then begin
                    //AddMessage('1 assigned');
                    tmpVal := getValueAsVariant(curProp1, nil);
                    setStructMember(s2, curName, getValueAsVariant(curProp1, nil));
                    RemoveElement(s1, curProp1);
                end else if(assigned(curProp2)) then begin
                    //AddMessage('2 assigned');
                    setStructMember(s1, curName, getValueAsVariant(curProp2, nil));
                    RemoveElement(s2, curProp2);
                end;
            end;
        end;

        tempNames.free();
    end;

    procedure resyncPowerGrid(parent: IInterface; iIndexOffset: integer);
    var
        i, curIndex, powerIndexOffset, newPowerIndex, oldPowerIndex: integer;
        curItem, curStruct: IInterface;
    begin
        // first, update the grid
        powerIndexOffset := iIndexOffset;
        for i:=0 to ElementCount(parent)-1 do begin
            oldPowerIndex := i + iIndexOffset;
            curStruct := ElementByIndex(parent, i);

            curIndex := getIndexForItem(curStruct);


            // curIndex := getIndexForItem(curStruct);
            // newPowerIndex := getNewPowerConnectionByItem(curStruct);
            //powerConnectionData

            if(isItemDeleted(curStruct)) then begin
            //if(entriesToDelete.indexOf(IntToStr(curIndex)) >= 0) then begin
                // deletion
                powerGridMapping.I[IntToStr(oldPowerIndex)] := 0;
                //AddMessage('Yes deletion for '+IntToStr(i));
                powerConnectionData.O[IntToStr(curIndex)].I['old'] := oldPowerIndex;
                powerConnectionData.O[IntToStr(curIndex)].I['new'] := -1;
                //powerConnectionData.I[IntToStr(curIndex)] := -1;
            end else begin
                powerGridMapping.I[IntToStr(oldPowerIndex)] := powerIndexOffset + 1;
                powerConnectionData.O[IntToStr(curIndex)].I['old'] := oldPowerIndex;
                powerConnectionData.O[IntToStr(curIndex)].I['new'] := powerIndexOffset;
                powerIndexOffset := powerIndexOffset + 1;
            end;

            {
            if(newPowerIndex < 0) then
                // a deletion
                // powerGridMapping
            end else begin
                // just put in what the current order is
                setNewPowerConnectionByItem(curStruct, powerIndexOffset);
                powerIndexOffset := powerIndexOffset + 1;
            end;
            }
        end;
    end;

    function isItemDeleted(item: IInterface): boolean;
    var
        curIndex, deleteIndex: integer;
    begin
        curIndex := getIndexForItem(item);

        deleteIndex := entriesToDelete.indexOf(IntToStr(curIndex));
        // AddMessage('isItemDeleted '+IntToStr(curIndex)+' -> '+IntToStr(deleteIndex));
        Result := (deleteIndex >= 0);
    end;

    procedure processEntriesToDelete(parent: IInterface);
    var
        i, curIndex, powerIndexOffset, newPowerIndex: integer;
        curItem, curStruct: IInterface;
        elemList: TList;
    begin
        elemList := TList.create();

        if(entriesToDelete.count <= 0) then begin
            exit;
        end;

        // actually delete
        AddMessage('Deleting '+IntToStr(entriesToDelete.count)+' merged entries');

        for i:=0 to entriesToDelete.count-1 do begin
            curIndex := StrToInt(entriesToDelete[i]);
            curItem := entriesLookupList[curIndex];

            entriesLookupList[curIndex] := nil;

            elemList.add(TObject(curItem));
            //RemoveElement(parent, curItem);
        end;

        for i:=0 to elemList.count-1 do begin
            RemoveElement(parent, ObjectToElement(elemList[i]));
        end;

        elemList.free();
        entriesToDelete.clear();
    end;

    function findNextUndeletedStructIndex(parent: IInterface; offset: Integer): integer;
    var
        i, powerIndex, curIndex: integer;
        curEntry: IInterface;
    begin
        for i:=offset to ElementCount(parent)-1 do begin

            curEntry := ElementByIndex(parent, i);
            //curIndex := getIndexForItem(curEntry);
            //if(entriesToDelete.indexOf(IntToStr(curIndex)) < 0) then begin
            if(not isItemDeleted(curEntry)) then begin
                Result := i;
                exit;
            end;
        end;

        Result := -1;
    end;

    procedure processEntriesToPrepend(parent: IInterface);
    var
        i, curIndex, swapIndex, powerIndexOld1, powerIndexOld2, powerIndexNew1, powerIndexNew2, curEntryIndex, otherEntryIndex: integer;
        curEntry, otherEntry: IInterface;
        gridData1, gridData2: TJsonObject;
    begin
        swapIndex := 0;
        for i:=0 to entriesToPrepend.count-1 do begin
            curEntry := ObjectToElement(entriesToPrepend[i]);
            curIndex := IndexOf(parent, curEntry);

            if(curIndex > swapIndex) then begin
                swapIndex := findNextUndeletedStructIndex(parent, swapIndex);
                otherEntry := ElementByIndex(parent, swapIndex);
                swapIndex := swapIndex + 1;

                //powerConnectionData.I[IntToStr(curIndex)] := powerIndexOffset;
                curEntryIndex := getIndexForItem(curEntry);
                otherEntryIndex := getIndexForItem(otherEntry);

                gridData1 := powerConnectionData.O[IntToStr(curEntryIndex)];
                gridData2 := powerConnectionData.O[IntToStr(otherEntryIndex)];

                powerIndexOld1 := gridData1.I['old'];
                powerIndexOld2 := gridData2.I['old'];
                powerIndexNew1 := gridData1.I['new'];
                powerIndexNew2 := gridData2.I['new'];

                // the indices in here are +1, but this shouldn't matter
                powerGridMapping.I[IntToStr(powerIndexOld1)] := powerIndexNew2;
                powerGridMapping.I[IntToStr(powerIndexOld2)] := powerIndexNew1;

                {
                AddMessage('=== SWAPPING ===');
                dumpElem(curEntry);
                AddMessage('----------------');
                dumpElem(otherEntry);
                AddMessage('================');
                }

                swapStructs(curEntry, otherEntry);
            end;
        end;

        entriesToPrepend.clear();
    end;

    procedure addItemToLayout(itemArray, form: IInterface; posX, posY, posZ: float; iType: integer);
    var
        newEntry: IInterface;
        id, newItemIndex, newPowerIndex: cardinal;
        // lastPrependIndex: integer;
        fileName: string;
    begin

        newEntry := appendStructToProperty(itemArray);
        if(not assigned(newEntry)) then begin
            AddMessage('[VERY BAD] Failed to add new entry to itemArray');
            exit;
        end;

        newItemIndex := ElementCount(itemArray);
        newPowerIndex := entriesLookupList.add(TObject(newEntry));


        //lookupIndex := entriesLookupList.add(TObject(item));
        // registerPowerConnection(newPowerIndex, newItemIndex, 2);

        // AddMessage('Setting new index from adding: '+IntToStr(newPowerIndex));
        // setNewPowerConnectionByIndex(newItemIndex, newPowerIndex);

        if(iType <> STATIC_TYPE_CLUTTER) then begin
            entriesToPrepend.add(TObject(newEntry));
        end;

        setStructMember(newEntry, 'ObjectForm', form);


        setStructMember(newEntry, 'fPosX', posX);
        setStructMember(newEntry, 'fPosY', posY);
        setStructMember(newEntry, 'fPosZ', posZ);
        // setStructMember(newEntry, 'iType', iType);

    end;

    procedure addItemToLayer(itemArray, form: IInterface; posX, posY, posZ: float; iRemoveAtLevel, iType: integer);
    var
        newEntry: IInterface;
        id: cardinal;
        // lastPrependIndex: integer;
        fileName: string;
    begin

        newEntry := appendStructToProperty(itemArray);
        if(not assigned(newEntry)) then begin
            AddMessage('[VERY BAD] Failed to add new entry to itemArray');
            exit;
        end;

        if(iType <> STATIC_TYPE_CLUTTER) then begin
            entriesToPrepend.add(TObject(newEntry));
        end;

        id := (FormID(form) and $00FFFFFF);
        fileName := GetFileName(GetFile(form));

        //AddMessage('before setting formID');
        setStructMember(newEntry, 'formID', id);
        //AddMessage('before setting formplugin');
        setStructMember(newEntry, 'FormPlugin', fileName);


        setStructMember(newEntry, 'fPositionX', posX);
        setStructMember(newEntry, 'fPositionY', posY);
        setStructMember(newEntry, 'fPositionZ', posZ);
        setStructMember(newEntry, 'iType', iType);

        if(iRemoveAtLevel <> 0) then begin
            setStructMember(newEntry, 'iRemoveAtLevel', iRemoveAtLevel);
        end else begin
            deleteStructMember(newEntry, 'iRemoveAtLevel');
        end;
        // addmessage('addItemToLayer DONE');
    end;

    procedure generateScolsForLayout(layout: IInterface);
    var
        i, j, k, l, structIndex, iIndexOffset: integer;
        rootX, rootY, rootZ: float;
        numPlacements, numOldRecords: integer;
        staticTypeStr, formIdStr, edid: string;

        staticTypesObj, contentsObj, curPlacementObj, vectorRootPos, vectorMinPos, vectorMaxPos: TJsonObject;
        formIdPlacements: TJsonArray;

        curScol, scolParts, curPartForm, curPart, curPartData, curPlacement, layerScript, itemArray: IInterface;
    begin
        edid := EditorID(layout);

        //currentPrependIndex := 0;
        entriesToDelete.clear();

        BeginUpdate(layout);

        layerScript := getScript(layout, 'SimSettlementsV2:Weapons:CityPlanLayout');


        itemArray := getScriptProp(layerScript, 'NonResourceObjects');
        iIndexOffset := getScriptPropDefault(layerScript, 'iIndexOffset', 0);

        AddMessage('Generating SCOLs for '+edid+' BEGIN');

        for i:=0 to curLayerJson.count-1 do begin
            staticTypeStr := curLayerJson.names[i];
            staticTypesObj := curLayerJson.O[staticTypeStr];

            //for j:=0 to staticTypesObj.count-1 do begin

               // removeAtLevelStr := staticTypesObj.names[j];
                //removeAtLevelObj := staticTypesObj.O[removeAtLevelStr];

                numPlacements := staticTypesObj.I['numPlacements'];
                numOldRecords := staticTypesObj.I['numOldRecords'];
                if (numPlacements <= 1) or (numOldRecords <= 1) then begin
                    AddMessage('Not enough items for type='+staticTypeStr+', skipping');
                    continue;
                end;
                AddMessage('Generating SCOL for type='+staticTypeStr);

                vectorRootPos := staticTypesObj.O['sumPos'];

                vectorMinPos := staticTypesObj.O['minPos'];
                vectorMaxPos := staticTypesObj.O['maxPos'];


                vectorRootPos := VectorDivide(vectorRootPos, numPlacements);

                vectorMinPos := VectorSubtract(vectorMinPos, vectorRootPos);
                vectorMaxPos := VectorSubtract(vectorMaxPos, vectorRootPos);

                contentsObj := staticTypesObj.O['contents'];

                curScol := createScol(edid+'_'+staticTypeStr);
                BeginUpdate(curScol);

                //AddMessage('Before setting the min bounds');
                // the bounds are actually integers
                SetElementEditValues(curScol, 'OBND\X1', floor(vectorMinPos.F['x']));
                SetElementEditValues(curScol, 'OBND\Y1', floor(vectorMinPos.F['y']));
                SetElementEditValues(curScol, 'OBND\Z1', floor(vectorMinPos.F['z']));

                //AddMessage('Before setting the max bounds');
                SetElementEditValues(curScol, 'OBND\X2', ceil(vectorMaxPos.F['x']));
                SetElementEditValues(curScol, 'OBND\Y2', ceil(vectorMaxPos.F['y']));
                SetElementEditValues(curScol, 'OBND\Z2', ceil(vectorMaxPos.F['z']));
                //AddMessage('After setting the bounds');


                scolParts := ensurePath(curScol, 'Parts');
                // as so often, we get one empty part by default. use it for the dummy

                curPart := ElementByIndex(scolParts, 0);
                // AddMessage('Got PivotDummy part? '+BoolToStr(assigned(curPart)));
                SetPathLinksTo(curPart, 'ONAM - Static', pivotDummy);
                curPartData := EnsurePath(curPart, 'DATA - Placements');
                curPlacement := ElementByIndex(curPartData, 0);
                SetElementEditValues(curPlacement, 'Scale', 1.0);


                for k := 0 to contentsObj.count-1 do begin
                    formIdStr := contentsObj.names[k];
                    formIdPlacements := contentsObj.A[formIdStr];


                    curPartForm := getFormByLoadOrderFormID(StrToInt(formIdStr));
                    // AddMessage('Trying to get '+formIdStr+', assigned? '+BoolToStr(assigned(curPartForm)));
                    curPart := ElementAssign(scolParts, HighInteger, nil, False);
                    // AddMessage('Appended element to SCOL? '+BoolToStr(assigned(curPart)));
                    SetPathLinksTo(curPart, 'ONAM - Static', curPartForm);


                    curPartData := EnsurePath(curPart, 'DATA - Placements');

                    for l := 0 to formIdPlacements.count-1 do begin
                        curPlacementObj := formIdPlacements.O[l];
                        curPlacement := ElementAssign(curPartData, HighInteger, nil, False);

                        SetElementEditValues(curPlacement, 'Position\X', curPlacementObj.F['posX'] - vectorRootPos.F['x']);
                        SetElementEditValues(curPlacement, 'Position\Y', curPlacementObj.F['posY'] - vectorRootPos.F['y']);
                        SetElementEditValues(curPlacement, 'Position\Z', curPlacementObj.F['posZ'] - vectorRootPos.F['z']);

                        SetElementEditValues(curPlacement, 'Rotation\X', curPlacementObj.F['rotX']);
                        SetElementEditValues(curPlacement, 'Rotation\Y', curPlacementObj.F['rotY']);
                        SetElementEditValues(curPlacement, 'Rotation\Z', curPlacementObj.F['rotZ']);
                        SetElementEditValues(curPlacement, 'Scale', curPlacementObj.F['scale']);

                        structIndex := curPlacementObj.I['IInterface'] - 1;
                        if(structIndex >= 0) then begin
                            // register removal
                            registerEntryForDeletion(structIndex);
                            // entriesToDelete.add(IntToStr(structIndex));
                            // setPowerConnectionData(str);
                            // RemoveElement(itemArray, ObjectToElement(entriesToDelete[structIndex]));
                        end;
                    end;
                end;

                // put the scol into the layer
                // AddMessage('addItemToLayout: StaticType: '+StaticTypeStr+', SCOL: '+EditorID(curScol));
                addItemToLayout(
                    itemArray,
                    curScol,
                    vectorRootPos.F['x'],
                    vectorRootPos.F['y'],
                    vectorRootPos.F['z'],
                    StrToInt(StaticTypeStr)
                );

                EndUpdate(curScol);

                vectorRootPos.free();
                vectorMinPos.free();
                vectorMaxPos.free();
           // end;
        end;

        AddMessage('Resyncing power grid');
        resyncPowerGrid(itemArray, iIndexOffset);

        AddMessage('Processing prepending');
        processEntriesToPrepend(itemArray);

        // delete the entries marked for deletion
        processEntriesToDelete(itemArray);

        EndUpdate(layout);

        AddMessage('Generating SCOLs for '+edid+' DONE');
    end;

    function processItemStructSS2(item: IInterface; connIndex, connType: integer): boolean;
    var
        iRemoveAtLevel, iType, iBlueprintIndex, iAppearAtLevel, staticType, i, lookupIndex: integer;
        formId: cardinal;
        posX, posY, posZ, rotX, rotY, rotZ, scale: float;
        forceStatic, highEndOnly: bool;
        srcPlugin, srcFormSig, staticTypeStr, removeAtLevelStr, formIdString: string;
        curScolBase, curPlacement, vectorTotalPos, vectorMinPos, vectorMaxPos: TJsonObject;
        srcFile, srcForm: IInterface;
    begin
        Result := false;

        lookupIndex := entriesLookupList.add(TObject(item));

        // registerPowerConnection(lookupIndex, connIndex, connType);

        srcForm := getStructMember(item, 'ObjectForm');


        if(not assigned(srcForm)) then begin
            // only process stuff which is linked directly
            srcPlugin := getStructMember(item, 'sPluginName');
            if(not isMasterAllowed(srcPlugin)) then begin
                exit;
            end

            // otherwise it seems we can use this formPlugin+formID combo
            formID := getStructMemberDefault(item, 'iFormID', -1);

            if(formID < 0) then begin
                exit;
            end;

            srcFile := FindFile(srcPlugin);
            if(not assigned(srcFile)) then begin
                exit;
            end;

            srcForm := getFormByFileAndFormID(srcFile, formId);
            if(not assigned(srcForm)) then begin
                AddMessage('getFormByFileAndFormID failed for '+GetFileName(srcFile)+'; '+IntToHex(formId, 8));
                exit;
            end;
        end;

        srcFormSig := Signature(srcForm);


        if (srcFormSig <> 'STAT') and (srcFormSig <> 'SCOL') then begin
            // AddMessage('Form '+EditorID(srcForm)+' is not static, skipping');
            exit;
        end;

        // iBlueprintIndex := getStructMember(item, 'iBlueprintIndex');
        // highEndOnly := getStructMember(item, 'bHighEndPCOnly');
        // forceStatic := getStructMember(item, 'bForceStatic');

        rotX := getStructMemberDefault(item, 'fAngleX', 0.0);
        rotY := getStructMemberDefault(item, 'fAngleY', 0.0);
        rotZ := getStructMemberDefault(item, 'fAngleZ', 0.0);
        posX := getStructMemberDefault(item, 'fPosX', 0.0);
        posY := getStructMemberDefault(item, 'fPosY', 0.0);
        posZ := getStructMemberDefault(item, 'fPosZ', 0.0);
        scale := getStructMemberDefault(item, 'fScale', 1.0);

        /// SCOL
        if(srcFormSig = 'SCOL') then begin
            staticTypeStr := IntToStr(STATIC_TYPE_OTHER);
            Result := processMergeScol(newVector(posX, posY, posZ), newVector(rotX, rotY, rotZ), scale, item, srcForm, curLayerJson.O[staticTypeStr], lookupIndex);
            exit;
        end;

        staticType := getStaticType(srcForm);


        if(staticType = 0) then begin
            // AddMessage('SKIPPING form: '+EditorID(srcForm)+' because it''s not whitelisted');
            exit;
        end;

        AddMessage('Adding static: '+EditorID(srcForm));

        Result := true;

        staticTypeStr := IntToStr(staticType);
        //removeAtLevelStr := IntToStr(iRemoveAtLevel);
        formIdString := '$'+IntToHex(GetLoadOrderFormID(srcForm), 8);

        curScolBase := curLayerJson.O[staticTypeStr];//.O[removeAtLevelStr];

        vectorTotalPos := curScolBase.O['sumPos'];
        vectorMinPos := curScolBase.O['minPos'];
        vectorMaxPos := curScolBase.O['maxPos'];
        // vectorTotalPos, vectorMinPos, vectorMaxPos

        vectorTotalPos.F['x'] := vectorTotalPos.F['x']+posX;
        vectorTotalPos.F['y'] := vectorTotalPos.F['y']+posY;
        vectorTotalPos.F['z'] := vectorTotalPos.F['z']+posZ;

        if(vectorMinPos.F['x'] > posX) then begin
            vectorMinPos.F['x'] := posX;
        end;

        if(vectorMinPos.F['y'] > posY) then begin
            vectorMinPos.F['y'] := posY;
        end;

        if(vectorMinPos.F['z'] > posZ) then begin
            vectorMinPos.F['z'] := posZ;
        end;


        if(vectorMaxPos.F['x'] < posX) then begin
            vectorMaxPos.F['x'] := posX;
        end;

        if(vectorMaxPos.F['y'] < posY) then begin
            vectorMaxPos.F['y'] := posY;
        end;

        if(vectorMaxPos.F['z'] < posZ) then begin
            vectorMaxPos.F['z'] := posZ;
        end;


        curScolBase.I['numOldRecords'] := curScolBase.I['numOldRecords']+1;
        curScolBase.I['numPlacements'] := curScolBase.I['numPlacements']+1;

        curPlacement := curScolBase.O['contents'].A[formIdString].AddObject();

        curPlacement.F['posX'] := posX;
        curPlacement.F['posY'] := posY;
        curPlacement.F['posZ'] := posZ;

        curPlacement.F['rotX'] := rotX;
        curPlacement.F['rotY'] := rotY;
        curPlacement.F['rotZ'] := rotZ;

        curPlacement.F['scale'] := scale;
        //AddMessage('Yes not scol');
        curPlacement.I['IInterface'] := lookupIndex + 1;//entriesToDelete.add(TObject(item));

        // setPowerConnectionData(connIndex, connType, -1);
    end;

    procedure processLayout(layout: IInterface);
    var
        script, NonResourceObjects, curStruct: IInterface;
        i, iIndexOffset, curIndex: integer;
    begin
        script := getScript(layout, 'SimSettlementsV2:Weapons:CityPlanLayout');
        if(not assigned(script)) then begin
            AddMessage('No layout script on '+EditorID(layout));
            exit;
        end;

        // check NonResourceObjects only
        NonResourceObjects := getScriptProp(script, 'NonResourceObjects');
        if(not assigned(NonResourceObjects)) then begin
            AddMessage('No NonResourceObjects on '+EditorID(layout));
            exit;
        end;

        iIndexOffset := getScriptPropDefault(script, 'iIndexOffset', 0);
        currentLayoutIndexOffset := iIndexOffset;

        curLayerJson := TJsonObject.create();
        AddMessage('=== ANALYZING LAYOUT '+EditorID(layout)+' ===');
        for i:=0 to ElementCount(NonResourceObjects)-1 do begin
            curStruct := ElementByIndex(NonResourceObjects, i);
            curIndex := iIndexOffset + i;

            // type = 2 here

            processItemStructSS2(curStruct, curIndex, 2);
        end;

        // AddMessage(curLayerJson.toString());
        AddMessage('=== GENERATING SCOLs FOR LAYOUT '+EditorID(layout)+' ===');
        generateScolsForLayout(layout);
        AddMessage('=== DONE ===');

        // AddMessage(powerGridMapping.toString());

        entriesToDelete.clear();
        // entriesLookupList.clear();
        entriesToPrepend.clear();
        curLayerJson.free();
    end;

    procedure postProcessLayout(layout: IInterface);
    var
        script, curStruct, powerGrid: IInterface;
        i, iIndexA, iIndexB, iIndexTypeA, iIndexTypeB, newIndexA, newIndexB: integer;
    begin
        script := getScript(layout, 'SimSettlementsV2:Weapons:CityPlanLayout');
        if(not assigned(script)) then begin
            exit;
        end;

        powerGrid := getScriptProp(script, 'PowerConnections');
        if(not assigned(powerGrid)) then begin
            exit;
        end;

        for i:=0 to ElementCount(powerGrid)-1 do begin
            curStruct := ElementByIndex(powerGrid, i);

            iIndexA := getStructMemberDefault(curStruct, 'iIndexA', 0);
            iIndexB := getStructMemberDefault(curStruct, 'iIndexB', 0);
            iIndexTypeA := getStructMemberDefault(curStruct, 'iIndexTypeA', 0);
            iIndexTypeB := getStructMemberDefault(curStruct, 'iIndexTypeB', 0);

            if(iIndexTypeA = 2) then begin
                // newIndexA := getNewPowerConnectionByOld(iIndexA, iIndexTypeA);
                newIndexA := powerGridMapping.I[IntToStr(iIndexA)] - 1;

                if ((newIndexA > -1) and (newIndexA <> iIndexA)) then begin
                    setStructMember(curStruct, 'iIndexA', newIndexA);
                end;
            end;

            if(iIndexTypeB = 2) then begin
                // newIndexB := getNewPowerConnectionByOld(iIndexB, iIndexTypeB);
                newIndexB := powerGridMapping.I[IntToStr(iIndexB)] - 1;
                if ((newIndexB > -1) and (newIndexB <> iIndexB)) then begin
                    setStructMember(curStruct, 'iIndexB', newIndexB);
                end;
            end;
        end;
    end;


    procedure fillCache(formList: IInterface; cacheList: TStringList; cacheFileName: string);
    var
        i, size, curFileAge: integer;
        curForm: IInterface;
        edid, formIdEdid, cacheFilePath: string;
    begin

        cacheFilePath := ScriptsPath +'SS2\'+ cacheFileName;

        if(fileExists(cacheFilePath)) then begin
            AddMessage('Loading whitelist '+cacheFileName);
            // don't do this age checking in here anymore
            cacheList.loadFromFile(cacheFilePath);
            exit;
        end;

        if(not assigned(formList)) then begin
            exit;
        end;

        size := getFormListLength(formList);
        formIdEdid := EditorID(formList);
        AddMessage('Building cache for '+formIdEdid + ' ('+intToStr(size)+' entries, this will take a while...)');
        for i:=0 to size-1 do begin
            curForm := getFormListEntry(formList, i);
            edid := EditorID(curForm);
            cacheList.add(edid);

            if (i > 0) then begin
                if(i mod 200 = 0) then begin
                    AddMessage('Processed '+IntToStr(i)+'/'+IntToStr(size));
                end;
            end;
        end;
        AddMessage('Cache built, saving to '+cacheFilePath);
        cacheList.saveToFile(cacheFilePath);
    end;

    function showConfigDialog(): boolean;
    var
        frm: TForm;
        btnOk, btnCancel: TButton;
        cbUseBlacklist, cbScolUsage, cbNavmeshed, cbColorRemap: TCheckBox;
        scolGroup: TGroupBox;
        resultCode : integer;
    begin
        Result := false;

        frm := CreateDialog('Plot Converter', 370, 240);


        cbUseBlacklist := CreateCheckbox(frm, 10, 10, 'Use Blacklist from '+edidListFileName_Blacklist);
        cbUseBlacklist.checked := true;


        // scolGroup

        cbScolUsage := CreateCheckbox(frm, 10, 40, 'Add objects used in other SCOLs');
        cbScolUsage.showHint := true;
        cbScolUsage.hint := 'If enabled, the script will add statics used in any other SCOL, as long as they are not blacklisted.';
        //CreateLabel(frm, 10, 50, 'The blacklist will have priority over this.');

        scolGroup := CreateGroup(frm, 10, 70, 360, 70, 'Options for objects from other SCOLs');
        cbNavmeshed := CreateCheckbox(scolGroup, 10, 20, 'Ignore navmeshed objects');
        cbNavmeshed.checked := true;
        cbNavmeshed.showHint := true;
        cbNavmeshed.hint := 'Navmeshes of objects have no effect if SCOLed';
        //CreateLabel(scolGroup, 10, 40, 'SCOLs ignore navmeshes of their constituents.');
        cbColorRemap:= CreateCheckbox(scolGroup, 10, 50,'Ignore objects with color remapping');
        cbColorRemap.checked := true;
        cbColorRemap.showHint := true;
        cbColorRemap.hint := 'Color remapping can''t be properly set for SCOLs, at least not automatically. If you uncheck this, you might get white cars.';

        //CreateLabel(scolGroup, 10, 80, 'The Color Remapping Index setting can''t be properly set for SCOLs');

        btnOk := CreateButton(frm, 50, 170, 'Start');
        btnOk.ModalResult := mrYes;
        btnOk.Default := true;

        btnCancel := CreateButton(frm, 250, 170, 'Cancel');
        btnCancel.ModalResult := mrCancel;


        resultCode := frm.ShowModal;

        if(resultCode <> mrYes) then begin
            frm.free();
            exit;
        end;

        checkScolUsage   := cbScolUsage.checked;
        ignoreNavmeshed  := cbNavmeshed.checked;
        ignoreColorRemap := cbColorRemap.checked;
        useBlacklist     := cbUseBlacklist.checked;
        Result := true;

        frm.free();

    end;

    // Called before processing
    // You can remove it if script doesn't require initialization code
    function Initialize: integer;
    begin
        Result := 0;

        simSettMaster := FindFile('SS2.esm');

        if(not assigned(simSettMaster)) then begin
            AddMessage('FATAL: Could not find SS2.esm');
            Result := 1;
            exit;
        end;

        if(not showConfigDialog()) then begin
            Result := 1;
            exit;
        end;

        simSettFileAge := FileAge(DataPath+'SS2.esm');

        // these seem to no longer exist
        kgSIM_CPSCOLWhitelist_Clutter   := FindObjectByEdid('kgSIM_CPSCOLWhitelist_Clutter');
        kgSIM_CPSCOLWhitelist_Other     := FindObjectByEdid('kgSIM_CPSCOLWhitelist_Other');
        kgSIM_CPSCOLWhitelist_Structure := FindObjectByEdid('kgSIM_CPSCOLWhitelist_Structure');

        kgSIM_FarHarborRequired := FindObjectByEdid('kgSIM_FarHarborRequired');
        kgSIM_NukaWorldRequired := FindObjectByEdid('kgSIM_NukaWorldRequired');

        pivotDummy := FindObjectByEdid('StaticCollectionPivotDummy');

        entriesToDelete := TStringList.Create;
        entriesLookupList := TList.Create;
        entriesToPrepend := TList.Create;

        formCache_Clutter := TStringList.create;
        formCache_Other := TStringList.create;
        formCache_Structure := TStringList.create;

        powerConnectionData := TJsonObject.create;
        powerGridMapping := TJsonObject.create;

        formCache_Clutter.sorted := true;
        formCache_Other.sorted := true;
        formCache_Structure.sorted := true;

        fillCache(kgSIM_CPSCOLWhitelist_Clutter, formCache_Clutter, edidListFileName_Clutter);
        fillCache(kgSIM_CPSCOLWhitelist_Other, formCache_Other, edidListFileName_Other);
        fillCache(kgSIM_CPSCOLWhitelist_Structure, formCache_Structure, edidListFileName_Structure);
        // AddMessage('Caching complete');

        // blacklist?
        scolBlacklist := TStringList.create;
        if(useBlacklist) then begin
            if(fileExists(edidListFileName_Blacklist)) then begin
                AddMessage('Loading blacklist from '+edidListFileName_Blacklist);
                scolBlacklist.loadFromFile(ScriptsPath + 'SS2\' + edidListFileName_Blacklist);
            end;
        end;

    end;

    // called for every record selected in xEdit
    function Process(e: IInterface): integer;
    var
        planScript, layouts, layout: IInterface;
        i: integer;
    begin
        Result := 0;

        targetFile := GetFile(e);
        hasFarHarbor := HasMaster(targetFile, 'DLCCoast.esm');
        hasNukaWorld := HasMaster(targetFile, 'DLCNukaWorld.esm');

        planScript := getScript(e, 'SimSettlementsV2:Weapons:CityPlan');
        if(not assigned(planScript)) then exit;

        layouts := getScriptProp(planScript, 'Layouts');
        //processLayer(e);

        for i:=0 to ElementCount(layouts)-1 do begin
            //dumpElem(ElementByIndex(layouts, i));

            layout := getObjectFromProperty(layouts, i);

            processLayout(layout);
        end;


        AddMessage('Postprocessing layouts...');
        // and again
        for i:=0 to ElementCount(layouts)-1 do begin
            //dumpElem(ElementByIndex(layouts, i));

            layout := getObjectFromProperty(layouts, i);

            postProcessLayout(layout);
        end;


        AddMessage('=== ALL DONE ===');
    end;

    // Called after processing
    // You can remove it if script doesn't require finalization code
    function Finalize: integer;
    begin
        Result := 0;
        entriesToDelete.free();
        entriesLookupList.free();

        powerConnectionData.free();
        powerGridMapping.free();

        formCache_Clutter.free();
        formCache_Other.free();
        formCache_Structure.free();
    end;

end.