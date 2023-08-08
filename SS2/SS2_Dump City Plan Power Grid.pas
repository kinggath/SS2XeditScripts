{
    New script template, only shows processed records
    Assigning any nonzero value to Result will terminate script
}
unit DumpPowerGrid;

    uses 'SS2\SS2Lib';
    uses 'SS2\CobbLibrary';

    var
        targetFile: IInterface;
        gridData: TJsonArray;

    // Called before processing
    // You can remove it if script doesn't require initialization code
    function Initialize: integer;
    begin
        Result := 0;
        gridData := TJsonArray.create();
    end;

    function resolvePowerIndex(layouts: IInterface; powerIndex, powerType: integer): TJsonObject;
    var
        i, j, iIndexOffset, curTargetIndex: integer;
        layerScript, objects, curObj, targetForm, layout: IInterface;
        key: string;
    begin
        Result := nil;
        if(powerType <> 1) and (powerType <> 2) then begin
            exit;
        end;

        for i:=0 to ElementCount(layouts)-1 do begin
            layout := getObjectFromProperty(layouts, i);
            layerScript := getScript(layout, 'SimSettlementsV2:Weapons:CityPlanLayout');
            iIndexOffset := getScriptPropDefault(layerScript, 'iIndexOffset', 0);

            if(iIndexOffset > powerIndex) then begin
                continue;
            end;

            if(powerType = 1) then begin
                key := 'WorkshopResources';
            end else begin
                key := 'NonResourceObjects';
            end;
            objects := getScriptProp(layerScript, key);

            curTargetIndex := powerIndex - iIndexOffset;

            if(curTargetIndex < ElementCount(objects)) then begin
                curObj := ElementByIndex(objects, curTargetIndex);
                targetForm := getStructMember(curObj, 'ObjectForm');

                Result := TJsonObject.create;
                Result.S['edid'] := EditorID(targetForm);
                Result.F['X'] := getStructMemberDefault(curObj, 'fPosX', 0.0);
                Result.F['Y'] := getStructMemberDefault(curObj, 'fPosY', 0.0);
                Result.F['Z'] := getStructMemberDefault(curObj, 'fPosZ', 0.0);
                Result.S['type'] := key;
                Result.I['index'] := curTargetIndex;
                Result.S['layout'] := EditorID(layout);
                Result.I['origIndex'] := powerIndex;
                exit;
            end;
            // processLayout(layouts, layout);
        end;
    end;
    
    function gridDataToStr(data: TJsonObject): string;
    begin
        if(data = nil) then begin
            Result := '[not found]';
            exit;
        end;
        
        Result := data.S['origIndex'] + ': ' + data.S['edid'] + ' in '+data.S['layout']+'::'+data.S['type']+' #'+IntToStr(data.I['index'])+' at ('+FloatToStr(data.F['X'])+' / '+FloatToStr(data.F['Y'])+' / '+FloatToStr(data.F['Z'])+')';
    end;

    procedure processLayout(layouts, layout: IInterface);
    var
        script, PowerGrid, ResourceObjects, NonResourceObjects, curStruct: IInterface;
        curEntry, gridEntry, gridData1, gridData2: TJsonObject;
        gridArray: TJsonArray;
        i, iIndexOffset, curIndex: integer;


    begin
        script := getScript(layout, 'SimSettlementsV2:Weapons:CityPlanLayout');
        if(not assigned(script)) then begin
            AddMessage('No layout script on '+EditorID(layout));
            exit;
        end;

        PowerGrid := getScriptProp(script, 'PowerConnections');
        iIndexOffset := getScriptPropDefault(script, 'iIndexOffset', 0);


        //curEntry := gridData.addObject();//TJsonObject.create();
        //curEntry.I['iIndexOffset'] := iIndexOffset;

        //gridArray := curEntry.A['grid'];
        AddMessage('Power Grid of Layout '+EditorID(layout));
        AddMessage('================');
        for i:=0 to ElementCount(PowerGrid)-1 do begin
            curStruct := ElementByIndex(PowerGrid, i);
            //gridEntry := gridArray.addObject();
            gridData1 := resolvePowerIndex(layouts, getStructMemberDefault(curStruct, 'iIndexA', 0), getStructMemberDefault(curStruct, 'iIndexTypeA', 0));
            gridData2 := resolvePowerIndex(layouts, getStructMemberDefault(curStruct, 'iIndexB', 0), getStructMemberDefault(curStruct, 'iIndexTypeB', 0));
            
            AddMessage('A: '+gridDataToStr(gridData1));
            AddMessage('B: '+gridDataToStr(gridData2));
            AddMessage('--------------');
            
            gridData1.free();
            gridData2.free();            
        end;

        // curEntry.free();
    end;

    procedure dumpGrid();
    var
        i, j: integer;
        layerData, layerGrid: TJsonObject;
    begin
        for i:=0 to gridData.count do begin
            layerData := gridData.O[i];

            layerGrid := layerData.A['grid'];
            // resolve
        end;
    end;

    // called for every record selected in xEdit
    function Process(e: IInterface): integer;
    var
        planScript, layouts, layout, powerConnections: IInterface;
        i: integer;
    begin
        Result := 0;

        targetFile := GetFile(e);

        planScript := getScript(e, 'SimSettlementsV2:Weapons:CityPlan');
        if(not assigned(planScript)) then exit;

        layouts := getScriptProp(planScript, 'Layouts');

        for i:=0 to ElementCount(layouts)-1 do begin
            layout := getObjectFromProperty(layouts, i);

            processLayout(layouts, layout);
        end;

    end;

    // Called after processing
    // You can remove it if script doesn't require finalization code
    function Finalize: integer;
    begin
        Result := 0;
        gridData.free();
    end;

end.