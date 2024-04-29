{
    Apply to city plan root
}
unit CityPlanConverter;

    uses 'SS2\SS2Lib';
    uses 'SS2\CobbLibrary';

    const
        configFile = ScriptsPath + 'SS2_CityPlanConverter.cfg';

    var
        plotData: TJsonObject;
        powerGridMap: TJsonObject;
        // oldFormPrefix: string;
		// newFormPrefix: string;
        sourceFile, targetFile, designerNameItem: IInterface;
        lastLayerOffset: integer;
        lastSelectedFileName: string;
        designerName: string;
        createPowerPoles: boolean;
        testMode: boolean;

    procedure loadConfig();
    var
        i, j, breakPos: integer;
        curLine, curKey, curVal: string;
        lines : TStringList;
    begin
        // default
        designerName := '';

        newFormPrefix := 'addon_';
        oldFormPrefix := '';
        lastSelectedFileName := '';
        createPowerPoles := true;
        testMode := false;

        if(not FileExists(configFile)) then begin
            exit;
        end;
        lines := TStringList.create;
        lines.LoadFromFile(configFile);

        //
        for i:=0 to lines.count-1 do begin
            curLine := lines[i];
            breakPos := -1;

            for j:=1 to length(curLine) do begin
                if(curLine[j] = '=') then begin
                    breakPos := j;
                    break;
                end;
            end;

            if breakPos <> -1 then begin
                curKey := trim(copy(curLine, 0, breakPos-1));
                curVal := trim(copy(curLine, breakPos+1, length(curLine)));

                if(curKey = 'DesignerName') then begin
                    designerName := curVal;
                end else if(curKey = 'NewPrefix') then begin
                    newFormPrefix := curVal;
                end else if(curKey = 'OldPrefix') then begin
                    oldFormPrefix := curVal;
                end else if(curKey = 'LastFile') then begin
                    lastSelectedFileName := curVal;
                end else if(curKey = 'CreatePowerPoles') then begin
                    createPowerPoles := StrToBool(curVal);
                end else if(curKey = 'TestMode') then begin
                    testMode := StrToBool(curVal);
                end;
            end;
        end;
        lines.free();

    end;

    procedure saveConfig();
    var
        lines : TStringList;
    begin
        lines := TStringList.create;
        lines.add('DesignerName='+designerName);
        lines.add('NewPrefix='+newFormPrefix);
        lines.add('OldPrefix='+oldFormPrefix);
        lines.add('LastFile='+GetFileName(targetFile));
        lines.add('CreatePowerPoles='+BoolToStr(createPowerPoles));
        lines.add('TestMode='+BoolToStr(testMode));

        lines.saveToFile(configFile);
        lines.free();
    end;


    {
        if oldFormPrefix is set, this will attempt to replace it with newFormPrefix + extraPrefix
    }
    function GenerateTranslatedEdid(prefix, edid: string): string;
    begin
        Result := generateEdid(prefix, stripPrefix(oldFormPrefix, edid));
    end;

    function canMasterBeUsed(masterName: string): boolean;
    var
        targetName: string;
    begin
        targetName := GetFileName(targetFile);
        if (masterName = targetName) or (masterName = 'SS2.esm') or (masterName = 'Fallout4.esm') then begin
            Result := true;
            exit;
        end;

        if(masterName = 'SimSettlements.esm') then begin
            Result := false;
            exit;
        end;


        Result := HasMaster(targetFile, masterName);
    end;

    {
        0 = use directly
        1 = use id/filename
        2 = translate
    }
    function getMasterType(masterName: string): integer;
    var
        sourceName: string;
    begin
        sourceName := GetFileName(sourceFile);
        if(masterName = 'SimSettlements.esm') or (masterName = sourceName) then begin
            Result := 2;
            exit;
        end;

        if(canMasterBeUsed(masterName)) then begin
            Result := 0;
            exit;
        end;

        Result := 1;
    end;

    procedure writeFormData_elem(struct: IInterface; elem: IInterface; elemKey: string);
    begin
        setStructMember(struct, elemKey, elem);
    end;

    procedure writeFormData_id(struct: IInterface; id: cardinal; pluginName, idKey, nameKey: string);
    begin
        setStructMember(struct, idKey, id);
        setStructMember(struct, nameKey, pluginName);
    end;

    procedure writeFormData(struct: IInterface; elem: IInterface; id: cardinal; pluginName, elemKey, idKey, nameKey: string);
    var
        fromFile: IInterface;
        masterType : integer;
        newEdid: string;
    begin

        if(assigned(elem)) then begin
            fromFile := GetFile(elem);
            pluginName := GetFileName(fromFile);

            if (canMasterBeUsed(pluginName)) then begin
                writeFormData_elem(struct, elem, elemKey);
                exit;
            end;

            id := getLocalFormId(fromFile, FormID(elem));
            writeFormData_id(struct, id, pluginName, idKey, nameKey);

            exit;
        end;

        if (canMasterBeUsed(pluginName)) then begin
            elem := getFormByFileAndFormID(FindFile(pluginName), id);
            if(assigned(elem)) then begin
                writeFormData_elem(struct, elem, elemKey);
                exit;
            end;

            writeFormData_id(struct, id, pluginName, idKey, nameKey);

            exit;
        end;

        writeFormData_id(struct, id, pluginName, idKey, nameKey);
    end;

    procedure writeUniversalForm_rec(script: IInterface; propName: string; rec: IInterface);
    var
        prop: IInterface;
    begin
        prop := getOrCreateScriptPropStruct(script, propName);
        setStructMember(prop, 'BaseForm', rec);
    end;


    procedure writeUniversalForm(script: IInterface; propName: string; rec: IInterface; id: cardinal; pluginName: string);
    var
        prop, formFile, elem: IInterface;
        formFileName: string;
        theFormId : cardinal;
    begin
        prop := getOrCreateScriptPropStruct(script, propName);
        //procedure writeFormData(struct: IInterface; elem: IInterface; id: cardinal; pluginName, elemKey, idKey, nameKey: string);
        writeFormData(prop, rec, id, pluginName, 'BaseForm', 'iFormID', 'sPluginName');
    end;

    function getNewPowerData(oldIndex: integer; level: integer): TJsonObject;
    var
        oldStrIndex: string;
    begin
        oldStrIndex := IntToStr(level) +'_'+ IntToStr(oldIndex);
        {if(powerGridMap.O[oldStrIndex].count <= 0) then begin
            return nu
        end;}
        Result := powerGridMap.O[oldStrIndex];
    end;

    procedure setNewPowerData(baseElem: IInterface; oldIndex, newIndex, newType, startLevel, removeAtLevel: integer);
    var
        oldStrIndex: string;
        hasConnector: boolean;
    begin
        oldStrIndex := IntToStr(startLevel) +'_'+ IntToStr(oldIndex);
        hasConnector := hasKeywordByPath(baseElem, 'WorkshopPowerConnection', 'KWDA');

        // AddMessage('DEBUG: Adding '+EditorID(baseElem)+' ('+IntToStr(oldIndex)+') as index='+IntToStr(newIndex)+', type='+IntToStr(newType)+', startLevel='+IntToStr(startLevel)+', endLevel='+IntToStr(removeAtLevel));

        if(powerGridMap.O[oldStrIndex].count > 0) then begin
            //
            if(powerGridMap.O[oldStrIndex].B['conn'] = true) then begin
                // let it in
                AddMessage('WARNING: Duplicate power grid index '+oldStrIndex+', skipping');
                exit;
            end else begin
                if(hasConnector) then begin
                    AddMessage('WARNING: Duplicate power grid index '+oldStrIndex+'. Old entry has no connector and will be replaced.');
                end else begin
                    AddMessage('WARNING: Duplicate power grid index '+oldStrIndex+', skipping. (neither has connector)');
                    exit;
                end;
            end;
        end;


        powerGridMap.O[oldStrIndex].I['index'] := newIndex;
        powerGridMap.O[oldStrIndex].I['type']  := newType;
        powerGridMap.O[oldStrIndex].I['start'] := startLevel;
        powerGridMap.O[oldStrIndex].I['end']   := removeAtLevel;
        powerGridMap.O[oldStrIndex].B['conn']  := hasConnector;

    end;

    procedure appendSpawn(baseElem: IInterface; curFileName: string; curFormId: cardinal; itemData: TJsonObject; targetArray: IInterface; isResObj: boolean; startLevel, removeAtLevel: integer);
    var
        newStruct, elem: IInterface;
        myIndex: integer;
        powerIndex, indexType: integer;
    begin
        myIndex := ElementCount(targetArray) + lastLayerOffset;
        newStruct := appendStructToProperty(targetArray);

        if(not assigned(baseElem)) then begin
            elem := getFormByFilenameAndFormID(curFileName, curFormId);
        end else begin
            elem := baseElem;
        end;

        writeFormData(newStruct, elem, curFormId, curFileName, 'ObjectForm', 'iFormID', 'sPluginName');

        setStructMemberDefault(newStruct, 'fPosX', itemData.F['fPositionX'], 0.0);
        setStructMemberDefault(newStruct, 'fPosY', itemData.F['fPositionY'], 0.0);
        setStructMemberDefault(newStruct, 'fPosZ', itemData.F['fPositionZ'], 0.0);

        setStructMemberDefault(newStruct, 'fAngleX', itemData.F['fRotationX'], 0.0);
        setStructMemberDefault(newStruct, 'fAngleY', itemData.F['fRotationY'], 0.0);
        setStructMemberDefault(newStruct, 'fAngleZ', itemData.F['fRotationZ'], 0.0);

        setStructMemberDefault(newStruct, 'fScale', itemData.F['fScale'], 1.0);
        setStructMemberDefault(newStruct, 'bForceStatic', itemData.F['bForceStatic'], false);

        // power
        powerIndex := itemData.I['iBlueprintIndex'];
        if (powerIndex < 0) then begin
            // AddMessage('powerIndex seems to be < 0: '+itemData.toString());
            //done
            exit;
        end;

        indexType := 1;
        if(not isResObj) then begin
            indexType := 2;
        end;

        setNewPowerData(elem, powerIndex, myIndex, indexType, startLevel, removeAtLevel);
    end;

    procedure writeScrapData(arr: TJsonArray; layerScript: IInterface; isRestore: boolean);
    var
        i: integer;
        propKey, FormPlugin: string;
        targetProp, newStruct: IInterface;
        itemData: TJsonObject;
        curFormId: cardinal;
    begin
        if(arr.count <= 0) then begin
            exit;
        end;

        propKey := 'VanillaObjectsToRestore';
        if(not isRestore) then begin
            propKey := 'VanillaObjectsToRemove';
        end;
        AddMessage('STARTING writing '+propKey);
        // WorldObject[] Property VanillaObjectsToRestore Auto Const
        // WorldObject[] Property VanillaObjectsToRemove Auto Const

        // kgSIM_RotC_CP_SanctuaryHills_Optimized "RotC: Sanctuary Hills" [MISC:0101993D]
        targetProp := getOrCreateScriptPropArrayOfStruct(layerScript, propKey);

        // AddMessage('Arr.count is '+IntToStr(arr.count));

        for i:=0 to arr.count-1 do begin
            itemData := arr.O[i];
            newStruct := appendStructToProperty(targetProp);


            setStructMemberDefault(newStruct, 'fPosX', itemData.F['fPositionX'], 0.0);
            setStructMemberDefault(newStruct, 'fPosY', itemData.F['fPositionY'], 0.0);
            setStructMemberDefault(newStruct, 'fPosZ', itemData.F['fPositionZ'], 0.0);

            setStructMemberDefault(newStruct, 'fAngleX', itemData.F['fRotationX'], 0.0);
            setStructMemberDefault(newStruct, 'fAngleY', itemData.F['fRotationY'], 0.0);
            setStructMemberDefault(newStruct, 'fAngleZ', itemData.F['fRotationZ'], 0.0);

            setStructMemberDefault(newStruct, 'fScale', itemData.F['fScale'], 1.0);

            curFormId := itemData.O['form'].I['form_id']; //getStructMemberDefault(curItem, 'FormID', 0);

            FormPlugin := itemData.O['form'].S['filename'];//getStructMemberDefault(curItem, 'FormPlugin', '');

            writeFormData(newStruct, nil, curFormId, FormPlugin, 'ObjectForm', 'iFormID', 'sPluginName');

            if ((i+1) mod 10) = 0 then begin
                AddMessage('Wrote '+IntToStr(i+1)+'/'+IntToStr(arr.count)+' items');
            end;

        end;

        AddMessage('FINISHED writing '+propKey);
    end;

    function writeNewCityPlanLayer(parentPlan: IInterface; edid: string; layerArray: IInterface; layerData: TJsonObject; startLevel, removeAtLevel: integer): IInterface;
    var
        layerForm, layerScript, resourceObjArray, nonResObjArray, arrayToUse, plotElem, layerKeyword: IInterface;
        layerEdid, curFileName, keywordEdid: string;
        itemData: TJsonArray;
        curItem: TJsonObject;
        i, plotType: integer;
        curFormId: cardinal;
        isResObj: bool;
    begin
        layerEdid := getShortEdid(edid, '_Layer_'+IntToStr(startLevel)+'_'+IntToStr(removeAtLevel));
        AddMessage('Writing SS2 Layer for Level '+IntToStr(startLevel)+' to '+IntToStr(removeAtLevel));
        layerForm := getCopyOfTemplate(targetFile, cityPlanLayerTemplate, layerEdid);

        Result := layerForm;

        BeginUpdate(Result);

        layerScript := getScript(layerForm, 'SimSettlementsV2:Weapons:CityPlanLayout');

        SetEditValueByPath(layerForm, 'FULL', plotData.O['meta'].S['name']+' Level '+IntToStr(startLevel)+' to '+IntToStr(removeAtLevel));

        setScriptProp(layerScript, 'ParentCityPlan', parentPlan);

        // easy stuff
        writeUniversalForm(layerScript, 'WorkshopRef', nil, plotData.O['WS'].I['form_id'], plotData.O['WS'].S['filename']);

        setScriptProp(layerScript, 'iIndexOffset', lastLayerOffset);

        setScriptProp(layerScript, 'iMinLevel', startLevel);
        if(removeAtLevel > 0) then begin
            setScriptProp(layerScript, 'iRemoveAtLevel', removeAtLevel);
        end;

        // keyword
        layerKeyword := getScriptProp(layerScript, 'TagKeyword');
        if(not assigned(layerKeyword)) then begin
            keywordEdid := getShortEdid(layerEdid, '_LayerKeyword');
            layerKeyword := getCopyOfTemplate(targetFile, keywordTemplate, keywordEdid);
            setScriptProp(layerScript, 'TagKeyword', layerKeyword);
        end;

        // items
        itemData := layerData.A['items'];
        if(itemData.count > 0) then begin
            AddMessage('STARTING writing '+IntToStr(itemData.count)+' items');
            for i:=0 to itemData.count-1 do begin
                curItem := itemData.O[i];
                curFileName := curItem.O['form'].S['filename'];
                curFormId   := curItem.O['form'].I['form_id'];

                // AddMessage('Would check: '+curFileName+' $'+IntToHex(curFormId, 8));

                isResObj := isResourceObject_id(curFileName, curFormId);
                // itemData: TJsonObject; targetArray: IInterface; isResObj: boolean);
                if(isResObj) then begin
                    if(not assigned(resourceObjArray)) then begin
                        resourceObjArray   := getOrCreateScriptPropArrayOfStruct(layerScript, 'WorkshopResources');
                    end;
                    arrayToUse := resourceObjArray;
                end else begin
                    if(not assigned(nonResObjArray)) then begin
                        nonResObjArray   := getOrCreateScriptPropArrayOfStruct(layerScript, 'NonResourceObjects');
                    end;
                    arrayToUse := nonResObjArray;
                end;

                appendSpawn(nil, curFileName, curFormId, curItem, arrayToUse, isResObj, startLevel, removeAtLevel);

                if((i+1) mod 10) = 0 then begin
                    AddMessage('Wrote '+IntToStr(i+1)+'/'+IntToStr(itemData.count)+' items');
                end;
                // exit; // DEBUG!
            end;
            AddMessage('FINISHED writing items');
        end;



        // plots
        itemData := layerData.A['plots'];

        if(itemData.count > 0) then begin
            AddMessage('STARTING writing '+IntToStr(itemData.count)+' plots');
            if(not assigned(resourceObjArray)) then begin
                resourceObjArray   := getOrCreateScriptPropArrayOfStruct(layerScript, 'WorkshopResources');
            end;

            for i:=0 to itemData.count-1 do begin
                curItem := itemData.O[i];

                plotType := curItem.I['type'];
                plotElem := getPlotActivatorByType(plotType);

                if (assigned(plotElem)) then begin
                    appendSpawn(plotElem, '', 0, curItem, resourceObjArray, true, startLevel, removeAtLevel);
                end;

                if((i+1) mod 10) = 0 then begin
                    AddMessage('Wrote '+IntToStr(i+1)+'/'+IntToStr(itemData.count)+' plots');
                end;
            end;
            AddMessage('FINISHED writing plots');
        end;


        writeScrapData(layerData.O['scrap'].A['add'], layerScript, true);
        writeScrapData(layerData.O['scrap'].A['remove'], layerScript, false);


        lastLayerOffset := lastLayerOffset + ElementCount(resourceObjArray) + ElementCount(nonResObjArray);

        EndUpdate(Result);
    end;

    function getNewConnStr(newConn: TJsonObject): string;
    begin
        Result := '('+IntToStr(newConn.I['type'])+'#'+IntToStr(newConn.I['index'])+')';
    end;

    // sort the power conns in the main meta into various layer's metas
    procedure sortPowerConnections();
    var
        i, startLevel, removeAtLevel, oldA, oldB, minLevelA, minLevelB, removeAtA, removeAtB, minLevelFinal, removeAtFinal, curLevel: integer;
        curLayer, layerScript: IInterface;
        oldPowerConns, targetPowerConns: TJsonArray;
        newA, newB, curLayerData: TJsonObject;
    begin
        oldPowerConns := plotData.O['meta'].A['powerConnections'];
        for i:=0 to oldPowerConns.count-1 do begin
            oldA := oldPowerConns.O[i].I['iBlueprintIndexA'];
            oldB := oldPowerConns.O[i].I['iBlueprintIndexB'];
            curLevel := oldPowerConns.O[i].I['level'];

            if(oldA = oldB) then begin
                AddMessage('=== Invalid connection ===');
                AddMessage('Old connection '+IntToStr(oldA)+' is supposed to be connected to itself?');
                continue;
            end;

            newA := getNewPowerData(oldA, curLevel);
            newB := getNewPowerData(oldB, curLevel);

            if(newA.count = 0) or(newB.count = 0) then begin
                AddMessage('=== Invalid connection in lvl'+IntToStr(curLevel)+' ===');
                AddMessage('Old connection: '+IntToStr(oldA)+' <--> '+IntToStr(oldB));
                AddMessage('New connection: '+getNewConnStr(newA)+' <--> '+getNewConnStr(newB));
                continue;
            end;

            minLevelA := newA['start'];
            removeAtA := newA['end'];

            minLevelB := newB['start'];
            removeAtB := newB['end'];

            // put the connection into the latest layer
            if(minLevelA > minLevelB) then begin
                // use data from A
                minLevelFinal := minLevelA;
                removeAtFinal := removeAtA;
            end else if(minLevelA < minLevelB) then begin
                // use data from B
                minLevelFinal := minLevelB;
                removeAtFinal := removeAtB;
            end else begin
                // use the highest removeAt, because that layer spawns later
                if(removeAtA > removeAtB) then begin
                    // a
                    minLevelFinal := minLevelA;
                    removeAtFinal := removeAtA;
                end else if(removeAtA > removeAtB) then begin
                    // b
                    minLevelFinal := minLevelB;
                    removeAtFinal := removeAtB;
                end else begin
                    // shouldn't matter, but use old index just in case
                    if(oldA > oldB) then begin
                        minLevelFinal := minLevelA;
                        removeAtFinal := removeAtA;
                    end else begin
                        minLevelFinal := minLevelB;
                        removeAtFinal := removeAtB;
                    end;
                end;
            end;

            if (not newA.B['conn']) or (not newB.B['conn']) then begin
                AddMessage('WARNING: At least one node seems to have no power connector: '+getNewConnStr(newA)+' <--> '+getNewConnStr(newB));
            end;

            // put it in
            targetPowerConns := plotData.O['layers'].O[IntToStr(minLevelFinal)].O[IntToStr(removeAtFinal)].O['meta'].A['powerConnections'];
            curLayerData := targetPowerConns.addObject();
            curLayerData.I['iBlueprintIndexA'] := oldA;
            curLayerData.I['iBlueprintIndexB'] := oldB;
            curLayerData.I['level'] := curLevel;
        end;
    end;

    procedure postprocessLayer(layer: IInterface);
    var
        layerScript, powerConnArray, newStruct: IInterface;
        startLevel, removeAtLevel, i, oldA, oldB, level: integer;
        oldPowerConns: TJsonArray;
        newA, newB: TJsonObject;
    begin
        layerScript := GetScript(layer, 'SimSettlementsV2:Weapons:CityPlanLayout');
        startLevel := getScriptProp(layerScript, 'iMinLevel');
        removeAtLevel := getScriptProp(layerScript, 'iRemoveAtLevel');

        AddMessage('Postprocessing '+EditorID(layer));


        oldPowerConns := plotData.O['layers'].O[IntToStr(startLevel)].O[IntToStr(removeAtLevel)].O['meta'].A['powerConnections'];

        if(oldPowerConns.count <= 0) then begin
            AddMessage('No old power connections, nothing to do');
            exit;
        end;
        AddMessage('Converting '+IntToStr(oldPowerConns.count)+' power connections');

        powerConnArray := getOrCreateScriptPropArrayOfStruct(layerScript, 'PowerConnections');

        for i:=0 to oldPowerConns.count-1 do begin
            oldA := oldPowerConns.O[i].I['iBlueprintIndexA'];
            oldB := oldPowerConns.O[i].I['iBlueprintIndexB'];
            level := oldPowerConns.O[i].I['level'];

            newA := getNewPowerData(oldA, level);
            newB := getNewPowerData(oldB, level);

{
            // this should be covered by sortPowerConnections() now
            if(newA.count = 0) or(newB.count = 0) then begin
                AddMessage('=== Invalid connection ===');
                AddMessage('Old connection: '+IntToStr(oldA)+' <--> '+IntToStr(oldB));
                AddMessage('New connection: '+newA.toString()+' <--> '+newB.toString());
                continue;
            end;
}


            newStruct := appendStructToProperty(powerConnArray);

            setStructMember(newStruct, 'iIndexA', newA.I['index']);
            setStructMember(newStruct, 'iIndexTypeA', newA.I['type']);

            setStructMember(newStruct, 'iIndexB', newB.I['index']);
            setStructMember(newStruct, 'iIndexTypeB', newB.I['type']);
        end;
    end;

    function debugFindPowerGridItem(powerIndex, powerType: integer; layerArray: IInterface): string;
    var
        i, curIndexOffset, relativeIndex: integer;
        curLayer, curSpawnStruct, curSpawn, layerScript, spawnArray: IInterface;
        arrayName: string;
    begin
        Result := 'Item '+IntToStr(powerIndex)+'/'+IntToStr(powerType) + ': ';

        for i:=0 to ElementCount(layerArray)-1 do begin
            curLayer := getObjectFromProperty(layerArray, i);
            layerScript := getScript(curLayer, 'SimSettlementsV2:Weapons:CityPlanLayout');
            curIndexOffset := getScriptProp(layerScript, 'iIndexOffset');

            if(curIndexOffset > powerIndex) then begin
                continue;
                // Result := Result + 'went over curIndexOffset';
                exit;
            end;

            relativeIndex := powerIndex - curIndexOffset;

            arrayName := 'WorkshopResources';
            if(powerType = 2) then begin
                arrayName := 'NonResourceObjects';
            end;

            spawnArray := getScriptProp(layerScript, arrayName);
            // AddMessage('### spawnArray ###');
            // AddMessage('count: '+IntToStr(ElementCount(spawnArray))+', relIndex='+IntToStr(relativeIndex));
            // dumpElem(spawnArray);
            //AddMEssage('### /spawnArray ###');
            if(ElementCount(spawnArray) <= relativeIndex) then begin
                // not there yet
                continue;
            end;

            curSpawnStruct := ElementByIndex(spawnArray, relativeIndex);
            if(not assigned(curSpawnStruct)) then begin
                // AddMessage('ARGH curSpawnStruct is shit');
                Result := Result + 'curSpawnStruct is not assigned';
                exit;
            end;
            curSpawn := getStructMember(curSpawnStruct, 'ObjectForm');
            if(not assigned(curSpawn)) then begin
                Result := Result + 'curSpawn is not assigned';
                // AddMEssage('### FUQ ###');
                // dumpElem(curSpawnStruct);
                exit;
            end;

            Result := Result + EditorID(curSpawn);
            exit;
            {
                    indexType := 1;
        if(not isResObj) then begin
            indexType := 2;
        end;

        SetEditValueByPath(layerForm, 'FULL', plotData.O['meta'].S['name']+' Level '+IntToStr(startLevel)+' to '+IntToStr(removeAtLevel));

        setScriptProp(layerScript, 'ParentCityPlan', parentPlan);

        // easy stuff
        writeUniversalForm(layerScript, 'WorkshopRef', nil, plotData.O['WS'].I['form_id'], plotData.O['WS'].S['filename']);

        setScriptProp(layerScript, 'iIndexOffset', lastLayerOffset);}
        end;

        Result := 'Item '+IntToStr(powerIndex)+'/'+IntToStr(powerType) + ': Found nothing';
    end;

    procedure debugDumpPowerGrid(layerArray: IInterface);
    var
        i, j, k, startLevel, removeAtLevel, oldA, oldB, level: integer;
        curLayer: IInterface;
        layerRoot, layerSub, layerData, newA, newB: TJsonObject;
        layerPower: TJsonArray;
        startLevelStr, removeAtLevelStr: string;
    begin
        layerRoot := plotData.O['layers'];
        AddMessage('=== BEGIN power grid dump ===');
        for i := 0 to layerRoot.count-1 do begin
            startLevelStr := layerRoot.names[i];
            startLevel := StrToInt(startLevelStr);

            layerSub := layerRoot.O[startLevelStr];
            for j:=0 to layerSub.count-1 do begin
                removeAtLevelStr := layerSub.names[j];
                removeAtLevel := StrToInt(removeAtLevelStr);

                layerData := layerSub.O[removeAtLevelStr];

                layerPower := layerData.O['meta'].A['powerConnections'];
                if(layerPower.count <= 0) then begin
                    continue;
                end;

                AddMessage('--- Layer '+startLevelStr+' -> '+removeAtLevelStr+' ---');
                for k:=0 to layerPower.count-1 do begin
                    oldA := layerPower.O[k].I['iBlueprintIndexA'];
                    oldB := layerPower.O[k].I['iBlueprintIndexB'];
                    // level := layerPower.O[k].I['level'];

                    newA := getNewPowerData(oldA, startLevel);
                    newB := getNewPowerData(oldB, startLevel);

                    AddMessage(
                        'Connection: '+
                        IntToStr(oldA)+'='+
                        //newA.toString()+'->'+
                        debugFindPowerGridItem(newA.I['index'], newA.I['type'], layerArray)+
                        '<-->'+
                        IntToStr(oldB)+'='+
                        //newB.toString()+'->'+
                        debugFindPowerGridItem(newB.I['index'], newB.I['type'], layerArray)
                    );
                end;
            end;
        end;
        AddMessage('=== Raw powerGridMap JSON: ===');
        AddMessage(powerGridMap.toString());
        AddMessage('=== END power grid dump ===');
    end;

    procedure writeNewCityPlan();
    var
        rootEdid: string;
        cpRoot, cpRootScript, descrOmod, newFlag, layerArray, writtenLayer, layerScript: IInterface;
        i, j, startLevel, removeAtLevel: integer;
        startLevelStr, removeAtLevelStr, designerNameItemEdid: string;
        layerRoot, layerSub, layerData: TJsonObject;
    begin
        rootEdid := GenerateTranslatedEdid(newFormPrefix+cityPlanPrefix, plotData.O['meta'].S['edid']);
        cpRoot := getCopyOfTemplate(targetFile, cityPlanRootTemplate, rootEdid);
        cpRootScript := getScript(cpRoot, 'SimSettlementsV2:Weapons:CityPlan');

        // jsonRoot.O[key].S['filename'] := filename;
        // jsonRoot.O[key].I['form_id'] := formId;
        SetEditValueByPath(cpRoot, 'FULL', plotData.O['meta'].S['name']);

        writeUniversalForm(cpRootScript, 'WorkshopRef', nil, plotData.O['WS'].I['form_id'], plotData.O['WS'].S['filename']);

        descrOmod := getCopyOfTemplate(targetFile, cityPlanDescriptionTemplate, rootEdid+'_Descr');

        SetEditValueByPath(descrOmod, 'FULL', plotData.O['meta'].S['author']);
        SetEditValueByPath(descrOmod, 'DESC', plotData.O['meta'].S['desc']);

        setScriptProp(cpRootScript, 'CityPlanDescription', descrOmod);

        setScriptProp(cpRootScript, 'iLevelCount', plotData.O['meta'].I['maxLevel']+1);


        generateTemplateCombination(cpRoot, descrOmod);

        // try layers
        //layerFlst := getElemByEdidAndSig(rootEdid+'_Layers', 'FLST', targetFile);
        //setScriptProp(cpRootScript,
        layerArray := getOrCreateScriptPropArrayOfObject(cpRootScript, 'Layouts');

        lastLayerOffset := 0;

        layerRoot := plotData.O['layers'];
        for i := 0 to layerRoot.count-1 do begin
            startLevelStr := layerRoot.names[i];
            startLevel := StrToInt(startLevelStr);

            layerSub := layerRoot.O[startLevelStr];
            for j:=0 to layerSub.count-1 do begin
                removeAtLevelStr := layerSub.names[j];
                removeAtLevel := StrToInt(removeAtLevelStr);

                layerData := layerSub.O[removeAtLevelStr];

                writtenLayer := writeNewCityPlanLayer(cpRoot, rootEdid, layerArray, layerData, startLevel, removeAtLevel);
                appendObjectToProperty(layerArray, writtenLayer);
            end;
        end;

        sortPowerConnections();

        // AddMessage('JSON IS NOW:');
        // AddMessage(plotData.toString());

        // AddMessage('NEW POWER GRID:');
        // AddMessage(powerGridMap.toString());

        AddMessage('Postprocessing Layers');
        for i:=0 to ElementCount(layerArray)-1 do begin
            writtenLayer := getObjectFromProperty(layerArray, i);
            if(not assigned(writtenLayer)) then begin
                AddMessage('FAILED TO WRITE A LAYER');
            end else begin
                // writtenLayer := LinksTo(ElementByIndex(layerArray, i));
                postprocessLayer(writtenLayer);
            end;
        end;

        // debugDumpPowerGrid(layerArray);

        // set designer name
        if(designerName <> '') then begin
            if(not assigned(designerNameItem)) then begin
                designerNameItemEdid := generateEdid(designNamePrefix, sanitizeEdidPart(designerName));
                designerNameItem := getElemByEdidAndSig(designerNameItemEdid, 'MISC', targetFile);
                SetElementEditValues(designerNameItem, 'FULL', designerName);
            end;

            // set it
            setScriptProp(cpRootScript, 'DesignerNameHolder', designerNameItem);
        end;

        // newFlag := translateForm();

        // registering
        AddMessage('Registering city plan');
        registerAddonContent(targetFile, cpRoot, SS2_FLID_CityPlans);
    end;

    {
        Shows the main config dialog, where you can select the target file and the prefixes
    }
    function showInitialConfigDialog(): boolean;
    var
        frm: TForm;
        btnOk, btnCancel: TButton;
        inputNewPrefix, inputOldPrefix, inputModName, inputDesignerName: TEdit;
        resultCode, i: integer;
        selectTargetFile: TComboBox;
        // checkShowPlotDialog: TCheckBox;
        s: string;
        curIndex, selectedIndex: integer;
        checkboxPoles, doTestMode: TCheckBox;
    begin
        loadConfig();

        Result := false;
        frm := CreateDialog('City Plan Converter', 370, 280);

        CreateLabel(frm, 10, 17, 'Target file');
        selectTargetFile := CreateComboBox(frm, 80, 15, 200, nil);
        selectTargetFile.Style := csDropDownList;
        selectTargetFile.Items.Add('-- CREATE NEW FILE --');

        selectedIndex := 0;

        for i := 0 to FileCount - 1 do begin
            s := GetFileName(FileByIndex(i));
            if (Pos(s, readOnlyFiles) > 0) then Continue;
            // selectTargetFile.Items.Add(s);

            curIndex := selectTargetFile.Items.Add(s);
            // AddMessage('Fu '+s+', '+lastSelectedFileName);
            if(s = lastSelectedFileName) then begin
                selectedIndex := curIndex;
            end;
        end;
        selectTargetFile.ItemIndex := selectedIndex;


        CreateLabel(frm, 10, 53, 'New prefix');
        inputNewPrefix  := CreateInput(frm, 80, 50, 'addon_');
        CreateLabel(frm, 210, 53, '(required)');

        CreateLabel(frm, 10, 73, 'Old prefix');
        inputOldPrefix  := CreateInput(frm, 80, 70, oldFormPrefix);
        CreateLabel(frm, 210, 73, '(optional)');
        CreateLabel(frm, 10, 93, 'The new prefix will be used for newly-generated forms.'+STRING_LINE_BREAK+'If old prefix is given, it will be replace by new prefix.');


        CreateLabel(frm, 10, 133, 'Designer Name');
        inputDesignerName := CreateInput(frm, 100, 130, designerName);
        CreateLabel(frm, 10, 153, 'The designer name be applied to all selected city plans.');



        // createPowerPoles
        checkboxPoles := CreateCheckbox(frm, 10, 170, 'Create Power Poles');
        checkboxPoles.checked := createPowerPoles;

        doTestMode := CreateCheckbox(frm, 10, 190, 'Test Mode');
        doTestMode.checked := testMode;



        btnOk := CreateButton(frm, 50, 220, 'Start Conversion');
        btnOk.ModalResult := mrYes;
        btnOk.Default := true;

        btnCancel := CreateButton(frm, 250, 220, 'Cancel');
        btnCancel.ModalResult := mrCancel;

        resultCode := frm.ShowModal;

        if(resultCode = mrYes) then begin
            newFormPrefix := trim(inputNewPrefix.text);
            oldFormPrefix := trim(inputOldPrefix.text);
            designerName  := trim(inputDesignerName.text);
            createPowerPoles := checkboxPoles.checked;
            testMode := doTestMode.checked;

            if(newFormPrefix = '') then begin
                AddMessage('You must enter a new prefix');
                exit;
            end;

            // maybe create a file
            if (selectTargetFile.ItemIndex = 0) then begin
                // add new here
                targetFile := AddNewFile
            end else begin
                for i := 0 to FileCount - 1 do begin
                    if (selectTargetFile.Text = GetFileName(FileByIndex(i))) then begin
                        targetFile := FileByIndex(i);
                        Break;
                    end;
                    if i = FileCount - 1 then begin
                        AddMessage('The script couldn''t find the file you entered.');
                        targetFile := ShowFileSelectDialog('Select another file');
                    end;
                end;
            end;
            if(assigned(targetFile)) then begin
                Result := true;
            end;
        end;

        frm.free();
    end;

    // Called before processing
    // You can remove it if script doesn't require initialization code
    function Initialize: integer;
    begin
        Result := 0;
        if(not showInitialConfigDialog()) then begin
            Result := 1;
        end;

        if(not initSS2Lib()) then begin
            Result := 1;
        end;

        saveConfig();
    end;

    function setExternalFormData(jsonRoot: TJsonObject; key, pluginName: string; id: cardinal): boolean;
    var
        masterType: integer;
        oldElem, elem, elemFile: IInterface;
    begin
        Result := false;
        if(pluginName = '') or (id = 0) then begin
            // AddMessage('Invalid form entry: '+pluginName+':'+IntToHex(id, 8));
            exit;
        end;

        // maybe convert it right away
        masterType := getMasterType(pluginName);
        {
            0 = use directly
            1 = use id/filename
            2 = translate
        }

        if(masterType = 2) then begin
            // AddMessage('Attempting to translate 0x'+IntToHex(id, 8)+' '+pluginName);

            oldElem := getFormByFilenameAndFormID(pluginName, id);
            if (not assigned(oldElem)) then begin
                // AddMessage('Failed to find 0x'+IntToHex(id, 8)+' in '+pluginName);
                AddMessage('Failed to find form '+pluginName+':'+IntToHex(id, 8);
                exit;
            end;


            elem := translateFormToFile(oldElem, sourceFile, targetFile);
            if(not assigned(elem)) then begin
                AddMessage('Failed to translate form '+pluginName+':'+IntToHex(id, 8)+' "'+EditorID(oldElem)+'"');
                exit;
            end;

            elemFile := GetFile(elem);

            jsonRoot.O[key].S['filename'] := GetFileName(elemFile);
            jsonRoot.O[key].I['form_id']  := getLocalFormId(elemFile, FormID(elem));

            Result := true;
            exit;
        end;


        jsonRoot.O[key].S['filename'] := pluginName;
        jsonRoot.O[key].I['form_id']  := id;
        Result := true;
    end;

    function getNewPlotType(oldForm: IInterface): integer;
    var
        script, flst : IInterface;
        flstEdid: string;
    begin
        Result := -1;
        script := getScript(oldForm, 'SimSettlements:SimPlot');
        if(not assigned(script)) then begin
            exit;
        end;

        flst := getScriptProp(script, 'BuildingPlanList');
        if(not assigned(flst)) then begin
            exit;
        end;

        flstEdid := EditorID(flst);

        if(flstEdid = 'kgSIM_MartialBuildingsList1x1') then begin
            Result := packPlotType(PLOT_TYPE_MAR, SIZE_1x1, -1);
            exit;
        end;

        if(flstEdid = 'kgSIM_MartialBuildingsList2x2') then begin
            Result := packPlotType(PLOT_TYPE_MAR, SIZE_2x2, -1);
            exit;
        end;

        if(flstEdid = 'kgSIM_MartialBuildingsList_Interior') then begin
            Result := packPlotType(PLOT_TYPE_MAR, SIZE_INT, -1);
            exit;
        end;

        if(flstEdid = 'kgSIM_CommercialBuildingPlans') then begin
            Result := packPlotType(PLOT_TYPE_COM, SIZE_2x2, -1);
            exit;
        end;

        if(flstEdid = 'kgSIM_CommercialBuildingsList_Interior') then begin
            Result := packPlotType(PLOT_TYPE_COM, SIZE_INT, -1);
            exit;
        end;

        if(flstEdid = 'kgSIM_AgriculturalBuildingsList_Interior') then begin
            Result := packPlotType(PLOT_TYPE_AGR, SIZE_INT, -1);
            exit;
        end;

        if(flstEdid = 'kgSIM_AgriculturalBuildingsListSizeA') then begin
            Result := packPlotType(PLOT_TYPE_AGR, SIZE_2x2, -1);
            exit;
        end;

        if(flstEdid = 'kgSIM_Agr3x3_BuildingPlans') then begin
            Result := packPlotType(PLOT_TYPE_AGR, SIZE_3x3, -1);
            exit;
        end;

        if(flstEdid = 'kgSIM_IndustrialAdvancedBuildingsListSize2x2') then begin
            Result := packPlotType(PLOT_TYPE_IND, SIZE_2x2, PLOT_SC_IND_Default_General); // hack
            exit;
        end;

        if(flstEdid = 'kgSIM_IndustrialBuildingsList_Interior') then begin
            Result := packPlotType(PLOT_TYPE_IND, SIZE_INT, -1);
            exit;
        end;

        if(flstEdid = 'kgSIM_IndustrialBuildingsListSizeA') then begin
            Result := packPlotType(PLOT_TYPE_IND, SIZE_2x2, -1);
            exit;
        end;

        if(flstEdid = 'kgSIM_RecreationalBuildingsList2x2') then begin
            Result := packPlotType(PLOT_TYPE_REC, SIZE_2x2, -1);
            exit;
        end;

        if(flstEdid = 'kgSIM_RecreationalBuildingsList_Interior') then begin
            Result := packPlotType(PLOT_TYPE_REC, SIZE_INT, -1);
            exit;
        end;

        if(flstEdid = 'kgSIM_ResidentialBuildingsList_Interior') then begin
            Result := packPlotType(PLOT_TYPE_RES, SIZE_INT, -1);
            exit;
        end;

        if(flstEdid = 'kgSIM_ResidentialBuildingsListSizeA') then begin
            Result := packPlotType(PLOT_TYPE_RES, SIZE_2x2, -1);
            exit;
        end;
    end;


    procedure applyPlotOffsets(curPlotType: integer; curPlotData: TJsonObject);
    var
        plotTypeMain, plotSize, plotTypeSub: integer;
        offsetX, offsetY, offsetZ, angleZ, sinAngle, cosAngle, offsetXNew, offsetYNew: float;
        offsetPos, offsetRot, plotPos, plotRot, transformed: TJsonObject;
    begin
        plotTypeMain := extractPlotMainType(curPlotType);
        plotSize := extractPlotSize(curPlotType);
        plotTypeSub := extractPlotSubtype(curPlotType); // adv. ind will have this as PLOT_SC_IND_Default_General, -1 for normal industrial
        {
        For Residential 2x2, Industrial 2x2, Commercial 2x2, and Agricultural 2x2, we need to shift -10 on the z and -46 on the Y.
        And then -10 on the Z for 1x1 Martial, 3x3 Agricultural, and Advanced Industrial.
        2x2 Martial has NO OFFSET
        }

        offsetX := 0.0;
        offsetY := 0.0;
        offsetZ := 0.0;


        case (plotSize) of
             SIZE_2x2:
                 begin
                    case (plotTypeMain) of
                        PLOT_TYPE_RES, PLOT_TYPE_COM, PLOT_TYPE_AGR, PLOT_TYPE_MAR:
                            begin
                                offsetY := -46.0;
                                offsetZ := -10.0;
                            end;
                        PLOT_TYPE_IND:
                            begin
                                if(plotTypeSub = PLOT_SC_IND_Default_General) then begin
                                    offsetZ := -10.0;
                                end else begin
                                    offsetY := -46.0;
                                    offsetZ := -10.0;
                                end;
                            end;
                        {
                        PLOT_TYPE_MAR:
                            begin
                                offsetZ := -10.0;
                            end;
                        }
                    end;
                 end;
             SIZE_1x1:
                begin
                    if(plotTypeMain = PLOT_TYPE_MAR) then begin
                        offsetZ := -10.0;
                    end;
                end;
            SIZE_3x3:
                begin
                    if(plotTypeMain = PLOT_TYPE_AGR) then begin
                        offsetZ := -10.0;
                    end;
                end;
        end;

        // easy shortcut
        if(offsetX = 0.0) and (offsetY = 0.0) and (offsetZ = 0.0) then begin
            exit;
        end;

        // transform
        offsetPos := newVector(offsetX, offsetY, offsetZ);
        offsetRot := newVector(0.0, 0.0, 0.0);

        plotPos := newVector(
            curPlotData.F['fPositionX'],
            curPlotData.F['fPositionY'],
            curPlotData.F['fPositionZ']
        );

        plotRot := newVector(
            curPlotData.F['fRotationX'],
            curPlotData.F['fRotationY'],
            curPlotData.F['fRotationZ']
        );

        transformed := GetCoordinatesRelativeToBase(plotPos, plotRot, offsetPos, offsetRot);

        curPlotData.F['fRotationX'] := transformed.O['rot'].F['x'];
        curPlotData.F['fRotationY'] := transformed.O['rot'].F['y'];
        curPlotData.F['fRotationZ'] := transformed.O['rot'].F['z'];

        curPlotData.F['fPositionX'] := transformed.O['pos'].F['x'];
        curPlotData.F['fPositionY'] := transformed.O['pos'].F['y'];
        curPlotData.F['fPositionZ'] := transformed.O['pos'].F['z'];

        transformed.free();
        offsetPos.free();
        offsetRot.free();
        plotPos.free();
        plotRot.free();
{

        if(offsetX = 0.0) and (offsetY = 0.0) then begin
            if (offsetZ <> 0.0) then begin
                curPlotData.F['fPositionZ'] := (curPlotData.F['fPositionZ'] + offsetZ);
            end;
            exit;
        end;

        angleZ := curPlotData.F['fRotationZ'];
        if(angleZ = 0.0) then begin
            curPlotData.F['fPositionX'] := (curPlotData.F['fPositionX'] + offsetX);
            curPlotData.F['fPositionY'] := (curPlotData.F['fPositionY'] + offsetY);
            curPlotData.F['fPositionZ'] := (curPlotData.F['fPositionZ'] + offsetZ);
            exit;
        end;

        // hard stuff
        sinAngle := sinDeg(angleZ);
        cosAngle := cosDeg(angleZ);

        // offsetXNew := offsetX * cosAngle - offsetY * sinAngle;
        // offsetYNew := offsetY * cosAngle + offsetX * sinAngle;

        offsetXNew := offsetX * cosAngle + offsetY * sinAngle;
        offsetYNew := offsetY * cosAngle - offsetX * sinAngle;




        curPlotData.F['fPositionX'] := (curPlotData.F['fPositionX'] + offsetXNew);
        curPlotData.F['fPositionY'] := (curPlotData.F['fPositionY'] + offsetYNew);
        curPlotData.F['fPositionZ'] := (curPlotData.F['fPositionZ'] + offsetZ);
}
    end;

    procedure importPlotPole(plotType: integer; curPlotData, plotData: TJsonObject; iBlueprintIndex, levelNr: integer);
    var
        plotElem, plotScript, poleForm, poleScript, poleStruct: IInterface;
        posX, posY, posZ, rotX, rotY, rotZ, scale: float;
        plotPos, plotRot, polePos, poleRot, transformed, curItemData: TJsonObject;
        curFormID: cardinal;
    begin
        plotElem := getPlotActivatorByType(plotType);
        plotScript := getScript(plotElem, 'SimSettlementsV2:ObjectReferences:SimPlot');

        poleForm := getScriptProp(plotScript, 'DefaultPowerPole');
        if(not assigned(poleForm)) then exit;

        AddMessage('Creating plot power pole: '+EditorID(poleForm));

        // now get the coords
        poleScript := getScript(poleForm, 'SimSettlementsV2:MiscObjects:PowerPole');
        poleStruct := getScriptProp(poleScript, 'SpawnData');

        polePos := newVector(
            getStructMemberDefault(poleStruct, 'fPosX', 0.0),
            getStructMemberDefault(poleStruct, 'fPosY', 0.0),
            getStructMemberDefault(poleStruct, 'fPosZ', 0.0)
        );

        poleRot := newVector(
            getStructMemberDefault(poleStruct, 'fAngleX', 0.0),
            getStructMemberDefault(poleStruct, 'fAngleY', 0.0),
            getStructMemberDefault(poleStruct, 'fAngleZ', 0.0)
        );

        scale := getStructMemberDefault(poleStruct, 'fScale', 1.0);
        poleForm := getStructMemberDefault(poleStruct, 'ObjectForm', 1.0);

        plotPos := newVector(
            curPlotData.F['fPositionX'],
            curPlotData.F['fPositionY'],
            curPlotData.F['fPositionZ']
        );

        plotRot := newVector(
            curPlotData.F['fRotationX'],
            curPlotData.F['fRotationY'],
            curPlotData.F['fRotationZ']
        );

        // ok, now transform this
        transformed := GetCoordinatesRelativeToBase(plotPos, plotRot, polePos, poleRot);

        curItemData := plotData.O['layers'].O[IntToStr(levelNr)].O['0'].A['items'].addObject();

        curFormID := FormID(poleForm) and $00FFFFFF;
        setExternalFormData(curItemData, 'form', GetFileName(GetFile(poleForm)), curFormID);

        curItemData.I['iBlueprintIndex'] := iBlueprintIndex;

        curItemData.F['fRotationX'] := transformed.O['rot'].F['x'];
        curItemData.F['fRotationY'] := transformed.O['rot'].F['y'];
        curItemData.F['fRotationZ'] := transformed.O['rot'].F['z'];

        curItemData.F['fPositionX'] := transformed.O['pos'].F['x'];
        curItemData.F['fPositionY'] := transformed.O['pos'].F['y'];
        curItemData.F['fPositionZ'] := transformed.O['pos'].F['z'];

        curItemData.F['fScale'] := scale;
        curItemData.B['bForceStatic'] := false;

        curItemData.I['iType'] := 0;
        curItemData.B['bHighEndPCOnly'] := false;

        transformed.free();
        polePos.free();
        poleRot.free();
        plotPos.free();
        plotRot.free();
    end;

    procedure importPlots(plotArray: IInterface; plotData: TJsonObject; startLevel: integer);
    var
        i: integer;
        curPlot, PlotForm: IInterface;
        BuildingPlanFormID, SkinFormID, VIPStoryFormID: cardinal;
        iBlueprintIndex, iAvailableAtLevel, curPlotType: integer;
        BuildingPlanPlugin, VIPStoryPlugin, SkinPlugin: string;
        fPositionX, fPositionY, fPositionZ, fRotationX, fRotationY, fRotationZ: float;
        curPlotData: TJsonObject;
        // bForceStatic: bool;
    begin
        for i:=0 to ElementCount(plotArray)-1 do begin
            curPlot := ElementByIndex(plotArray, i);
            BuildingPlanFormID := getStructMemberDefault(curPlot, 'BuildingPlanFormID', 0);
            BuildingPlanPlugin := getStructMemberDefault(curPlot, 'BuildingPlanPlugin', '');

            VIPStoryPlugin := getStructMemberDefault(curPlot, 'VIPStoryPlugin', '');
            VIPStoryFormID := getStructMemberDefault(curPlot, 'VIPStoryFormID', 0);

            SkinPlugin := getStructMemberDefault(curPlot, 'SkinPlugin', '');
            SkinFormID := getStructMemberDefault(curPlot, 'SkinFormID', 0);

            PlotForm := getStructMember(curPlot, 'PlotForm');

            iBlueprintIndex := getStructMemberDefault(curPlot, 'iBlueprintIndex', 0);

            fPositionX := getStructMemberDefault(curPlot, 'fPositionX', 0.0);
            fPositionY := getStructMemberDefault(curPlot, 'fPositionY', 0.0);
            fPositionZ := getStructMemberDefault(curPlot, 'fPositionZ', 0.0);

            fRotationX := getStructMemberDefault(curPlot, 'fRotationX', 0.0);
            fRotationY := getStructMemberDefault(curPlot, 'fRotationY', 0.0);
            fRotationZ := getStructMemberDefault(curPlot, 'fRotationZ', 0.0);

            iAvailableAtLevel := getStructMemberDefault(curPlot, 'iAvailableAtLevel', -1);

            if(iAvailableAtLevel < 0) then begin
                iAvailableAtLevel := startLevel;
            end;

            curPlotData := plotData.O['layers'].O[IntToStr(iAvailableAtLevel)].O['0'].A['plots'].addObject();

            // commented these out for now
            //setExternalFormData(curPlotData, 'buildingPlan', BuildingPlanPlugin, BuildingPlanFormID);
            //setExternalFormData(curPlotData, 'vipStory', VIPStoryPlugin, VIPStoryFormID);
            //setExternalFormData(curPlotData, 'buildingSkin', SkinPlugin, SkinFormID);

            curPlotType := getNewPlotType(PlotForm);

            curPlotData.I['type'] := curPlotType;
            curPlotData.I['iBlueprintIndex'] := -1;//iBlueprintIndex;

            curPlotData.F['fPositionX'] := fPositionX;
            curPlotData.F['fPositionY'] := fPositionY;
            curPlotData.F['fPositionZ'] := fPositionZ;

            curPlotData.F['fRotationX'] := fRotationX;
            curPlotData.F['fRotationY'] := fRotationY;
            curPlotData.F['fRotationZ'] := fRotationZ;

            curPlotData.F['fScale'] := 1.0;
            curPlotData.B['bForceStatic'] := false;

            // apply offsets
            applyPlotOffsets(curPlotType, curPlotData);

            // special hack: try to append the power pole to the items
            if(createPowerPoles) then begin
                importPlotPole(curPlotType, curPlotData, plotData, iBlueprintIndex, iAvailableAtLevel);
            end;
        end;
    end;

    procedure importItems(itemArray: IInterface; plotData: TJsonObject; startLevel: integer);
    var
        i, iBlueprintIndex, iAppearAtLevel, iRemoveAtLevel, iType, currentDataIndex: integer;
        curItem: IInterface;
        curLayerRoot, curLayerData: TJsonObject;
        bHighEndPCOnly, bForceStatic: boolean;
        fRotationX, fRotationY, fRotationZ, fPositionX, fPositionY, fPositionZ, fScale: float;
        curFormId: cardinal;
        FormPlugin: string;
    begin
        curLayerRoot := plotData.O['layers'].O[IntToStr(startLevel)];
        for i:=0 to ElementCount(itemArray)-1 do begin
            curItem := ElementByIndex(itemArray, i);
            iBlueprintIndex := getStructMemberDefault(curItem, 'iBlueprintIndex', -1);
            bHighEndPCOnly := getStructMemberDefault(curItem, 'bHighEndPCOnly', false);

            fRotationX := getStructMemberDefault(curItem, 'fRotationX', 0.0);
            fRotationY := getStructMemberDefault(curItem, 'fRotationY', 0.0);
            fRotationZ := getStructMemberDefault(curItem, 'fRotationZ', 0.0);

            fPositionX := getStructMemberDefault(curItem, 'fPositionX', 0.0);
            fPositionY := getStructMemberDefault(curItem, 'fPositionY', 0.0);
            fPositionZ := getStructMemberDefault(curItem, 'fPositionZ', 0.0);

            iAppearAtLevel := getStructMemberDefault(curItem, 'iAppearAtLevel', 0);
            iRemoveAtLevel := getStructMemberDefault(curItem, 'iRemoveAtLevel', 0);
            iType := getStructMemberDefault(curItem, 'iType', 0);

            fScale := getStructMemberDefault(curItem, 'fScale', 1.0);

            curFormId := getStructMemberDefault(curItem, 'FormID', 0);

            bForceStatic := getStructMemberDefault(curItem, 'bForceStatic', false);

            FormPlugin := getStructMemberDefault(curItem, 'FormPlugin', '');
// Struct CityPlanSpawn
// 	int iBlueprintIndex
// 	{ Will be used in the future for automating wire connections for players using F4SE }
// 	bool bHighEndPCOnly = False
// 	{ If this is checked, this object won't be spawned on Xbox, or for PC players who have the Detailed Objects performance option turned off }
// 	float fRotationX = 0
// 	int iRemoveAtLevel = 0
// 	{ City level this should be removed: 1, 2, 3, 0 to never remove, -1 to remove after everything else is built }
// 	float fPositionZ = 0
// 	int iAppearAtLevel = 0
// 	{ Earliest city level this should be created: 0, 1, 2, or 3 }
// 	int iType = 0
// 	{ Classification for things like resources. 0 = Normal, 1 = Food, 2 = Water, 3 = Generator, 4 = Turret, 5 = Non-food Job, 6 = Structural SCOL, 7 = Non-Structural SCOL, 8 = Clutter SCOL }
// 	float fScale = 1
// 	int FormID
// 	float fPositionY = 0
// 	bool bForceStatic = False
// 	{ Physics will be turned off for this object }
// 	float fPositionX = 0
// 	string FormPlugin
// 	float fRotationY = 0
// 	float fRotationZ = 0
// EndStruct
            if(FormPlugin <> '') and (curFormId > 0) then begin
                // write it
                curLayerData := curLayerRoot.O[IntToStr(iRemoveAtLevel)].A['items'].AddObject();

                currentDataIndex := curLayerRoot.O[IntToStr(iRemoveAtLevel)].A['items'].count-1;

                // procedure setExternalFormData(jsonRoot: TJsonObject; key, filename: string; formId: cardinal);

                if(setExternalFormData(curLayerData, 'form', FormPlugin, curFormId)) then begin
                    curLayerData.I['iBlueprintIndex'] := iBlueprintIndex;

                    curLayerData.B['bHighEndPCOnly'] := bHighEndPCOnly;

                    curLayerData.F['fRotationX'] := fRotationX;
                    curLayerData.F['fRotationY'] := fRotationY;
                    curLayerData.F['fRotationZ'] := fRotationZ;

                    curLayerData.F['fPositionX'] := fPositionX;
                    curLayerData.F['fPositionY'] := fPositionY;
                    curLayerData.F['fPositionZ'] := fPositionZ;

                    curLayerData.I['iType'] := iType;
                    curLayerData.F['fScale'] := fScale;
                    curLayerData.B['bForceStatic'] := bForceStatic;
                end else begin
                    //AddMessage('FAILED to set '+FormPlugin+' 0x'+IntToHex(curFormId, 8));
                    curLayerRoot.O[IntToStr(iRemoveAtLevel)].A['items'].delete(currentDataIndex);
                end;
            end;
        end;
    end;

    procedure importPowerConnections(powerConnArray: IInterface; plotData: TJsonObject; startLevel: integer);
    var
        i, iBlueprintIndexA, iBlueprintIndexB: integer;
        curConn: IInterface;
        curLayerArray: TJsonArray;
        curLayerData: TJsonObject;
    begin
        // curLayerArray := plotData.O['layers'].O[IntToStr(startLevel)].O['0'].O['meta'].A['powerConnections'];
        curLayerArray := plotData.O['meta'].A['powerConnections'];

        for i:=0 to ElementCount(powerConnArray)-1 do begin
            curConn := ElementByIndex(powerConnArray, i);
            iBlueprintIndexA := getStructMemberDefault(curConn, 'iBlueprintIndexA', -1);
            iBlueprintIndexB := getStructMemberDefault(curConn, 'iBlueprintIndexB', -1);

            if(iBlueprintIndexA >= 0) and (iBlueprintIndexB >= 0) then begin
                curLayerData := curLayerArray.addObject();
                curLayerData.I['iBlueprintIndexA'] := iBlueprintIndexA;
                curLayerData.I['iBlueprintIndexB'] := iBlueprintIndexB;
                curLayerData.I['level'] := startLevel;
            end;
        end;
    end;

    procedure processLayer(layer: IInterface; data: TJsonObject);
    var
        script, Items, PowerConnections, Plots, LayerAppliedMessage, ToggleGlobal: IInterface;
        Requirement_GlobalValues, Requirement_AppliedLayerKeywords, Requirement_WorkshopAVs, Requirement_LeaderAVs, curPlot: IInterface;
        PreferredFlagFormID: cardinal;
        PreferredFlagPlugin: string;
        layerLevel, LayerID: integer;
        bIgnorePerformanceOptions, bReplaceable: boolean;

        curLayerReqs, curLayerRoot, curLayerData: TJsonObject;
    begin
        // kgSIM_RotC_CPLayer_Covenant_Optimized_L2 "Level 2" [MISC:01019972]
        script := getScript(layer, 'SimSettlements:CityPlanLayer');
        if(not assigned(script)) then begin
            exit;
        end;

        Items := getScriptProp(script, 'Items');
        PowerConnections := getScriptProp(script, 'PowerConnections');
        Plots := getScriptProp(script, 'Plots');

        PreferredFlagFormID := getScriptPropDefault(script, 'PreferredFlagFormID', 0);
        PreferredFlagPlugin := getScriptPropDefault(script, 'PreferredFlagPlugin', '');

        LayerAppliedMessage := getScriptProp(script, 'LayerAppliedMessage');
        ToggleGlobal := getScriptProp(script, 'ToggleGlobal');

        layerLevel := getScriptPropDefault(script, 'Requirement_Level', 0);

        // DISREGARD REQUIREMENTS
        // Requirement_GlobalValues := getScriptProp(script, 'Requirement_GlobalValues');
        // this is just a list of forms
        // Requirement_AppliedLayerKeywords := getScriptProp(script, 'Requirement_AppliedLayerKeywords');
        // Requirement_WorkshopAVs := getScriptProp(script, 'Requirement_WorkshopAVs');
        // Requirement_LeaderAVs := getScriptProp(script, 'Requirement_LeaderAVs');
        // Requirement_QuestStages := getScriptProp(script, 'Requirement_QuestStages');
        {
    kghelpers:kghelperstructures:globalvaluemap[] Property Requirement_GlobalValues Auto Const
	Keyword[] Property Requirement_AppliedLayerKeywords Auto Const
	kghelpers:kghelperstructures:actorvaluemap[] Property Requirement_WorkshopAVs Auto Const
	kghelpers:kghelperstructures:actorvaluemap[] Property Requirement_LeaderAVs Auto Const
	kghelpers:kghelperstructures:queststage[] Property Requirement_QuestStages Auto Const
        }

        LayerID := getScriptPropDefault(script, 'LayerID', 0);

        bIgnorePerformanceOptions := getScriptPropDefault(script, 'bIgnorePerformanceOptions', false);
        bReplaceable := getScriptPropDefault(script, 'bReplaceable', false);

        // curPlotData := plotData.O['layers'].O[IntToStr(iAvailableAtLevel)].O['0'].A['plots'].addObject();
        // the actual layerData will be dependent on the item's stop
        curLayerRoot := plotData.O['layers'].O[IntToStr(layerLevel)];


        // write the easy stuff
        curLayerData := curLayerRoot.O['0'];
        // put in flag

        { if(PreferredFlagFormID > 0) then begin }
            { AddMessage('asdasd'); }
        { end; }

        //if(PreferredFlagPlugin <> '') and (PreferredFlagFormID > 0) then begin
        setExternalFormData(curLayerData.O['meta'], 'flagForm', PreferredFlagPlugin, PreferredFlagFormID);
        //end;

        if(assigned(LayerAppliedMessage)) then begin
            curLayerData.O['meta'].S['LayerAppliedMessage'] := EditorID(LayerAppliedMessage);
        end;

        if(assigned(ToggleGlobal)) then begin
            curLayerData.O['meta'].S['ToggleGlobal'] := EditorID(ToggleGlobal);
        end;

        if(assigned(Plots)) then begin
            // procedure importPlots(plotArray: IInterface; plotData: TJsonObject; startLevel: integer);
            importPlots(Plots, plotData, layerLevel);
        end;

        // now do items
        if(assigned(Items)) then begin
            importItems(Items, plotData, layerLevel);
        end;

        if(assigned(PowerConnections)) then begin
            importPowerConnections(PowerConnections, plotData, layerLevel);
        end;

        // update max levels
        if(layerLevel > plotData.O['meta'].I['maxLevel']) then begin
            plotData.O['meta'].I['maxLevel'] := layerLevel;
        end;
    end;

    procedure processScrapProfile(scrapProp: IInterface; toRestore: boolean; plotData: TJsonObject);
    var
        firstLevelData: TJsonArray;
        curLayerData: TJsonObject;
        jsonKey, FormPlugin: string;
        i, iBlueprintIndex, iAppearAtLevel, iRemoveAtLevel, iType: integer;
        curItem: IInterface;
        fRotationX, fRotationY, fRotationZ, fPositionX, fPositionY, fPositionZ, fScale: float;
        curFormId: cardinal;
    begin
        // convert
        // simsettlements:simstructures:cityplanspawn[] Property ScrapMe Auto Const
        // simsettlements:simstructures:cityplanspawn[] Property UnscrapMe Auto Const
        // into
        // WorldObject[] Property VanillaObjectsToRestore Auto Const
        // WorldObject[] Property VanillaObjectsToRemove Auto Const

        jsonKey := 'add';
        if(not toRestore) then begin
            jsonKey := 'remove';
        end;

        firstLevelData := plotData.O['layers'].O['0'].O['0'].O['scrap'].A[jsonKey];// .addObject();
        for i:=0 to ElementCount(scrapProp)-1 do begin
            curItem := ElementByIndex(scrapProp, i);
            // iBlueprintIndex := getStructMemberDefault(curItem, 'iBlueprintIndex', -1);
            // bHighEndPCOnly := getStructMemberDefault(curItem, 'bHighEndPCOnly', false);

            fRotationX := getStructMemberDefault(curItem, 'fRotationX', 0.0);
            fRotationY := getStructMemberDefault(curItem, 'fRotationY', 0.0);
            fRotationZ := getStructMemberDefault(curItem, 'fRotationZ', 0.0);

            fPositionX := getStructMemberDefault(curItem, 'fPositionX', 0.0);
            fPositionY := getStructMemberDefault(curItem, 'fPositionY', 0.0);
            fPositionZ := getStructMemberDefault(curItem, 'fPositionZ', 0.0);

            iAppearAtLevel := getStructMemberDefault(curItem, 'iAppearAtLevel', 0);
            iRemoveAtLevel := getStructMemberDefault(curItem, 'iRemoveAtLevel', 0);
            iType := getStructMemberDefault(curItem, 'iType', 0);

            fScale := getStructMemberDefault(curItem, 'fScale', 1.0);

            curFormId := getStructMemberDefault(curItem, 'FormID', 0);

            // bForceStatic := getStructMemberDefault(curItem, 'bForceStatic', false);

            FormPlugin := getStructMemberDefault(curItem, 'FormPlugin', '');

            if(FormPlugin <> '') and (curFormId > 0) then begin
                // write it
                curLayerData := firstLevelData.AddObject();

                // procedure setExternalFormData(jsonRoot: TJsonObject; key, filename: string; formId: cardinal);

                if(setExternalFormData(curLayerData, 'form', FormPlugin, curFormId)) then begin
                    // curLayerData.I['iBlueprintIndex'] := iBlueprintIndex;
//kgSIM_RotC_CP_BunkerHill "RotC: Bunker Hill" [MISC:0100AFF1]
                    // curLayerData.B['bHighEndPCOnly'] := bHighEndPCOnly;

                    curLayerData.F['fRotationX'] := fRotationX;
                    curLayerData.F['fRotationY'] := fRotationY;
                    curLayerData.F['fRotationZ'] := fRotationZ;

                    curLayerData.F['fPositionX'] := fPositionX;
                    curLayerData.F['fPositionY'] := fPositionY;
                    curLayerData.F['fPositionZ'] := fPositionZ;

                    curLayerData.I['iType'] := iType;
                    curLayerData.F['fScale'] := fScale;
                    // curLayerData.B['bForceStatic'] := bForceStatic;
                end else begin
                    AddMessage('FAILED to set '+FormPlugin+' 0x'+IntToHex(curFormId, 8));
                    curLayerData.remove();
                end;
            end;
        end;


    end;

    // called for every record selected in xEdit
    function Process(e: IInterface): integer;
    var
        script, layerFlst, extraPlaqueInfoMesg, scrapMe, unscrapMe, rootElemPlots, curLayer: IInterface;
        iExtraData, i, numLayers: integer;
        workbenchRefId: cardinal;
        workbenchFile, fullName: string;
        bHighEndOnly, bPlayerSelectOnly: boolean;
    begin
        Result := 0;
        script := getScript(e, 'SimSettlements:CityPlan');
        if(not assigned(script)) then begin
            exit;
        end;

        sourceFile := GetFile(e);

        // comment this out if you don't want those messages
        AddMessage('Processing: ' + FullPath(e));
        plotData := TJsonObject.create();
        powerGridMap := TJsonObject.create();

        workbenchRefId := getScriptProp(script, 'WorkbenchRefID');
        workbenchFile := getScriptProp(script, 'WorkbenchRefPlugin');

        extraPlaqueInfoMesg := getScriptProp(script, 'ExtraPlaqueInfo');
        layerFlst := getScriptProp(script, 'CityLayers');

        scrapMe := getScriptProp(script, 'ScrapMe');
        unscrapMe := getScriptProp(script, 'UnscrapMe');

        iExtraData := getScriptPropDefault(script, 'iExtraData', 0);

        bHighEndOnly := getScriptPropDefault(script, 'bHighEndOnly', false);
        bPlayerSelectOnly := getScriptPropDefault(script, 'bPlayerSelectOnly', false);

        fullName := geevt(e, 'FULL');


        setExternalFormData(plotData, 'WS', workbenchFile, workbenchRefId);
        // fill the easy stuff
        //plotData.O['WS'].S['filename'] := workbenchFile;
        //plotData.O['WS'].I['form_id'] := workbenchRefId;

        plotData.O['meta'].S['edid'] := EditorID(e);
        plotData.O['meta'].S['name'] := fullName;
        plotData.O['meta'].I['extraData'] := iExtraData;
        plotData.O['meta'].S['desc'] := geevt(extraPlaqueInfoMesg, 'DESC');
        plotData.O['meta'].S['author'] := geevt(extraPlaqueInfoMesg, 'FULL');
        plotData.O['meta'].S['bHighEndOnly'] := bHighEndOnly;
        plotData.O['meta'].S['bPlayerSelectOnly'] := bPlayerSelectOnly;
        plotData.O['meta'].I['maxLevel'] := 0;

        rootElemPlots := getScriptProp(script, 'plots');
        if(assigned(rootElemPlots)) then begin
            // kgSIM_RotC_CP_RedRocketTruckStop_Optimized "RotC: Red Rocket" [MISC:0101993E]
            importPlots(rootElemPlots, plotData, 0);
        end;

        // scrap profiles
        if(assigned(scrapMe)) then begin
            processScrapProfile(scrapMe, false, plotData);
        end;

        if(assigned(unscrapMe)) then begin
            processScrapProfile(unscrapMe, true, plotData);
        end;

        // now iterate the layers
        numLayers := getFormListLength(layerFlst);
        for i:=0 to numLayers-1 do begin
            curLayer := getFormListEntry(layerFlst, i);
            AddMessage('Reading SS1 Layer #'+IntToStr(i)+', '+EditorID(curLayer));
            processLayer(curLayer, plotData);
        end;

        if(testMode) then begin
            AddMessage('Test Mode! No SS2 City Plan will be written!');
        end else begin
            AddMessage('Finished reading layers, begin writing SS2 City Plan');
            writeNewCityPlan();
        end;

        plotData.free();
        powerGridMap.free();
    end;

    // Called after processing
    // You can remove it if script doesn't require finalization code
    function Finalize: integer;
    begin
        CleanMasters(targetFile);
        cleanupSS2Lib();
        Result := 0;
    end;

end.