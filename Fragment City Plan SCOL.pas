{
    run on SCOLs
}
unit FragmentCityPlanSCOL;

    uses 'SS2\SS2Lib';
    uses 'SS2\CobbLibrary';

    var
        pivotDummy: IInterface;

        simSettMaster: IInterface;

        curLayerJson: TJsonObject;

        entriesLookupList: TList;
        entriesToDelete: TStringList;
        entriesToPrepend: TList;

        targetFile: IInterface;

        powerGridMapping: TJsonObject;
        powerConnectionData: TJsonObject;
        currentLayoutIndexOffset: Integer;

        scolsToFragment: TStringList;
        layoutsToProcess: TStringList;

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
        AddMessage('Deleting '+IntToStr(entriesToDelete.count)+' entries');

        for i:=0 to entriesToDelete.count-1 do begin
            curIndex := StrToInt(entriesToDelete[i]);
            curItem := entriesLookupList[curIndex];

            entriesLookupList[curIndex] := nil;

            elemList.add(TObject(curItem));
            //RemoveElement(parent, curItem);
        end;

        for i:=0 to elemList.count-1 do begin
            curItem := ObjectToElement(elemList[i]);
            //AddMessage('Would be removing '+FullPath(curItem)+', from '+FullPath(parent));
            RemoveElement(parent, curItem);
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

    procedure addItemToLayoutFull(itemArray, form: IInterface; posX, posY, posZ, rotX, rotY, rotZ, scale: float);//; iType: integer
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


        // entriesToPrepend.add(TObject(newEntry));


        setStructMember(newEntry, 'ObjectForm', form);


        setStructMember(newEntry, 'fPosX', posX);
        setStructMember(newEntry, 'fPosY', posY);
        setStructMember(newEntry, 'fPosZ', posZ);

        setStructMemberDefault(newEntry, 'fAngleX', rotX, 0.0);
        setStructMemberDefault(newEntry, 'fAngleY', rotY, 0.0);
        setStructMemberDefault(newEntry, 'fAngleZ', rotZ, 0.0);

        setStructMemberDefault(newEntry, 'fScale', scale, 1.0);

    end;


    procedure fragmentScolsForLayout(layout: IInterface);
    var
        i, j, k, l, iIndexOffset, scolIndex: integer;
        posX, posY, posZ, rotX, rotY, rotZ, scale, partScale: float;
        edid, scaleString: string;


        layerScript, itemArray, curStruct, srcForm, partsRoot, curPart, curPartBase, curPlacement, placements: IInterface;
        scolPos, scolRot, partPosVector, partPosVectorScaled, partRotVector, rotatedData: TJsonObject;
    begin
        edid := EditorID(layout);
        AddMessage('=== Processing layout '+edid);

        //currentPrependIndex := 0;
        entriesToDelete.clear();

        BeginUpdate(layout);

        layerScript := getScript(layout, 'SimSettlementsV2:Weapons:CityPlanLayout');

        itemArray := getScriptProp(layerScript, 'NonResourceObjects');
        iIndexOffset := getScriptPropDefault(layerScript, 'iIndexOffset', 0);

        currentLayoutIndexOffset := iIndexOffset;

        for i:=0 to ElementCount(itemArray)-1 do begin
            curStruct := ElementByIndex(itemArray, i);
            srcForm := getStructMember(curStruct, 'ObjectForm');

            if(assigned(srcForm)) then begin
                if(scolsToFragment.indexOf(EditorID(srcForm)) >= 0) then begin

                // if(IsSameForm(srcForm, scol)) then begin

                    rotX := getStructMemberDefault(curStruct, 'fAngleX', 0.0);
                    rotY := getStructMemberDefault(curStruct, 'fAngleY', 0.0);
                    rotZ := getStructMemberDefault(curStruct, 'fAngleZ', 0.0);
                    posX := getStructMemberDefault(curStruct, 'fPosX', 0.0);
                    posY := getStructMemberDefault(curStruct, 'fPosY', 0.0);
                    posZ := getStructMemberDefault(curStruct, 'fPosZ', 0.0);
                    scale := getStructMemberDefault(curStruct, 'fScale', 1.0);


                    scolPos := newVector(posX, posY, posZ);
                    scolRot := newVector(rotX, rotY, rotZ);

                    // mark deleted?
                    scolIndex := getIndexForItem(curStruct);
                    registerEntryForDeletion(scolIndex);

                    partsRoot := ElementByPath(srcForm, 'Parts');
                    AddMessage('Fragmenting '+EditorID(srcForm)+' with '+IntToStr(ElementCount(partsRoot))+' parts');

                    // now iterate the components
                    for j:=0 to ElementCount(partsRoot)-1 do begin
                        curPart := ElementByIndex(partsRoot, j);
                        curPartBase := pathLinksTo(curPart, 'ONAM');
                        //AddMessage('curPartBase = '+EditorID(curPartBase));
                        if(GetLoadOrderFormID(curPartBase) = $00035812) then begin//StaticCollectionPivotDummy [STAT:00035812]
                            //AddMessage('skipping PivotDummy');
                            continue;
                        end;
                        placements := ElementByPath(curPart, 'DATA');
                        for k:=0 to ElementCount(placements)-1 do begin

                            curPlacement := ElementByIndex(placements, k);

                            partPosVector := getPositionVector(curPlacement, '');
                            partPosVectorScaled := VectorMultiply(partPosVector, scale);
                            partRotVector := getRotationVector(curPlacement, '');

                            partScale := 1.0;
                            scaleString := getElementEditValues(curPlacement, 'Scale');
                            if(scaleString <> '') then begin
                                partScale := StrToFloat(scaleString);
                            end;

                            rotatedData := GetCoordinatesRelativeToBase(scolPos, scolRot, partPosVectorScaled, partRotVector);

                            // now put it in
                            addItemToLayoutFull(
                                itemArray,
                                curPartBase,
                                rotatedData.O['pos'].F['x'],
                                rotatedData.O['pos'].F['y'],
                                rotatedData.O['pos'].F['z'],
                                rotatedData.O['rot'].F['x'],
                                rotatedData.O['rot'].F['y'],
                                rotatedData.O['rot'].F['z'],
                                scale*partScale

                            );

                            rotatedData.free();
                            partPosVector.free();
                            partPosVectorScaled.free();
                            partRotVector.free();
                        end;
                    end;
                    AddMessage('Fragmenting '+EditorID(srcForm)+' DONE');
                    scolPos.free();
                    scolRot.free();
                end;
            end;
        end;

        AddMessage('Resyncing power grid');
        resyncPowerGrid(itemArray, iIndexOffset);

        AddMessage('Processing prepending');
        processEntriesToPrepend(itemArray);

        // delete the entries marked for deletion
        processEntriesToDelete(itemArray);

        EndUpdate(layout);

        AddMessage('=== Processing layout '+edid+' DONE');
    end;


    function showConfigDialog(): boolean;
    var
        frm: TForm;
        btnOk, btnCancel: TButton;


        resultCode : integer;
    begin
        Result := false;

        frm := CreateDialog('Fragment SCOLs', 370, 240);




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
{
        if(not showConfigDialog()) then begin
            Result := 1;
            exit;
        end;
}
        //simSettFileAge := FileAge(DataPath+'SS2.esm');



        pivotDummy := FindObjectByEdid('StaticCollectionPivotDummy');

        entriesToDelete := TStringList.Create;
        entriesLookupList := TList.Create;
        entriesToPrepend := TList.Create;



        powerConnectionData := TJsonObject.create;
        powerGridMapping := TJsonObject.create;

        scolsToFragment := TStringList.create;
        layoutsToProcess:= TStringList.create;

    end;

    procedure processScol(scol: IInterface);
    var
        i, numRefs: integer;
        layouts: TStringList;
        curRef, curLayout: IInterface;
        edid: string;
    begin
        if(not isMaster(scol)) then begin
            initOverrideUpdating(GetFile(Master(scol)));
            //scol := getOverriddenForm(scol, targetFile);
        end;
        // find all layouts where this one is used, then for each, add each part as spawn, and remove self
        layouts := TStringList.create;
        numRefs := ReferencedByCount(scol)-1;
        for i:=0 to numRefs do begin
            curRef := ReferencedByIndex(scol, i);
            // accept if it has SimSettlementsV2:Weapons:CityPlanLayout
            if(assigned(getScript(curRef, 'SimSettlementsV2:Weapons:CityPlanLayout'))) then begin
                AddMessage('Found relevant layout: '+DisplayName(curRef));
                edid := EditorID(curRef);
                if(layouts.indexOf(edid) < 0) then begin
                    layouts.addObject(edid, curRef);
                end;
            end;
        end;

        for i:= 0 to layouts.count-1 do begin
            curLayout := ObjectToElement(layouts.Objects[i]);
            curLayout := getOverriddenForm(curLayout, targetFile);
            AddMessage('Doing layout: '+DisplayName(curLayout));
            fragmentScolForLayout(scol, curLayout);
        end;
        layouts.free();
    end;

    // called for every record selected in xEdit
    function Process(e: IInterface): integer;
    var
        curRef: IInterface;
        i, numRefs: integer;
        edid: string;
    begin
        Result := 0;
        if(Signature(e) <> 'SCOL') then exit;
        if(not assigned(targetFile)) then begin
            targetFile := GetFile(e);
            AddMessage('TargetFile is '+GetFileName(targetFile));
            if(not isMaster(e)) then begin
                initOverrideUpdating(targetFile);
            end;
        end;

        edid := EditorID(e);
        //i := scolsToFragment.indexOf(edid);
        if(scolsToFragment.indexOf(edid) < 0) then begin
            scolsToFragment.addObject(edid, e);
            numRefs := ReferencedByCount(e)-1;
            for i:=0 to numRefs do begin
                curRef := ReferencedByIndex(e, i);
                // accept if it has SimSettlementsV2:Weapons:CityPlanLayout
                if(assigned(getScript(curRef, 'SimSettlementsV2:Weapons:CityPlanLayout'))) then begin
                    AddMessage('Found relevant layout: '+EditorID(curRef));
                    edid := EditorID(curRef);
                    if(layoutsToProcess.indexOf(edid) < 0) then begin
                        layoutsToProcess.addObject(edid, curRef);
                    end;
                end;
            end;

        end;



        //processScol(e);

    end;

    // Called after processing
    // You can remove it if script doesn't require finalization code
    function Finalize: integer;
    var
        i: integer;
        curLayout: IInterface;
    begin
        // do the stuff here
        for i:=0 to layoutsToProcess.count-1 do begin
            curLayout := ObjectToElement(layoutsToProcess.Objects[i]);
            curLayout := getOverriddenForm(curLayout, targetFile);
            fragmentScolsForLayout(curLayout);
        end;

        Result := 0;
        entriesToDelete.free();
        entriesLookupList.free();

        powerConnectionData.free();
        powerGridMapping.free();

        scolsToFragment.free();
        layoutsToProcess.free();
    end;

end.