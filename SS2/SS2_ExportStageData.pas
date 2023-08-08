{
    New script template, only shows processed records
    Assigning any nonzero value to Result will terminate script

    [ ] Skins
}
unit userscript;
    uses 'SS2\SS2Lib'; // uses praUtil
    // uses dubhFunctions; // dubhFunctions uses mteFunctions
    
    const
        spawnsFileHeader = 'Form,Pos X,Pos Y,Pos Z,Rot X,Rot Y,Rot Z,Scale,iLevel,iStageNum,iStageEnd,iType,sVendorType,iVendorLevel,iOwnerNumber,sSpawnName,Requirements';

    var
        currentBlueprint: IInterface;

    function getCsvLineForSpawn(curItem: IInterface; curLevel: integer; addStageNums: boolean): string;
    var
        iStageNum, iStageEnd, iType, iOwnerNumber: integer;
        detailsScript, detailsForm, spawnDetails, spawnForm, reqForm: IInterface;
        posX, posY, posZ, rotX, rotY, rotZ, scale: float;
        currentLine, spawnName: string;
    begin
        if(addStageNums) then begin
            iStageNum := getStructMemberDefault(curItem, 'iStageNum', -1);
            iStageEnd := getStructMemberDefault(curItem, 'iStageEnd', -1);
        end else begin
            iStageNum := 0;
            iStageEnd := 0;
        end;

        iOwnerNumber := getStructMember(curItem, 'iOwnerNumber');
        detailsForm := getStructMember(curItem, 'StageItemDetails');

        detailsScript := getScript(detailsForm, 'SimSettlementsV2:MiscObjects:StageItem');

        spawnDetails := getScriptProp(detailsScript, 'SpawnDetails');

        // read all the data
        posX := getStructMemberDefault(spawnDetails, 'fPosX', 0.0);
        posY := getStructMemberDefault(spawnDetails, 'fPosY', 0.0);
        posZ := getStructMemberDefault(spawnDetails, 'fPosZ', 0.0);

        rotX := getStructMemberDefault(spawnDetails, 'fAngleX', 0.0);
        rotY := getStructMemberDefault(spawnDetails, 'fAngleY', 0.0);
        rotZ := getStructMemberDefault(spawnDetails, 'fAngleZ', 0.0);

        scale := getStructMemberDefault(spawnDetails, 'fScale', 1.0);

        iType := getScriptPropDefault(detailsScript, 'iType', 0);


        spawnForm := getStructMember(spawnDetails, 'ObjectForm');
        reqForm   := getStructMemberDefault(spawnDetails, 'Requirements', nil);

        spawnName := getStructMemberDefault(spawnDetails, 'sSpawnName', '');

        currentLine := EditorID(spawnForm);

        // ohnno fix for excel-like programs trying to be "smart"...
        currentLine := currentLine + ',' + FormatFloat( '#####0.000000', posX) + ',' + FormatFloat( '#####0.000000',posY) + ',' + FormatFloat( '#####0.000000',posZ) + ',' + FormatFloat( '#####0.000000',rotX) + ',' + FormatFloat( '#####0.000000',rotY) + ',' + FormatFloat( '#####0.000000',rotZ);

        currentLine := currentLine + ',' + FormatFloat( '#####0.000000', scale);

        currentLine := currentLine + ',' + FloatToStr(curLevel);


        if(iStageNum > 0) then begin
            currentLine := currentLine + ',' + FloatToStr(iStageNum);
        end else begin
            currentLine := currentLine + ',';
        end;

        if(iStageEnd > 0) then begin
            currentLine := currentLine + ',' + FloatToStr(iStageEnd);
        end else begin
            currentLine := currentLine + ',';
        end;

        if(iType <> 0) then begin
            currentLine := currentLine + ',' + IntToStr(iType);
        end else begin
            currentLine := currentLine + ',';
        end;

        // vendor type
        currentLine := currentLine + ',';
        // vendor level
        currentLine := currentLine + ',';

        // owner number
        if(iOwnerNumber > 0) then begin
            currentLine := currentLine + ',' + IntToStr(iOwnerNumber);
        end else begin
            currentLine := currentLine + ',';
        end;

        //spawnName
        currentLine := currentLine + ',' + spawnName;

        // reqs
        if(assigned(reqForm)) then begin
            currentLine := currentLine + ',' + EditorID(reqForm);
        end else begin
            currentLine := currentLine + ',';
        end;

        Result := currentLine;
    end;

    procedure exportBuildingPlanItems(curPlan: IInterface; list: TStringList);
    var
        planScript, planItems, curItem: IInterface;
        curLevel: integer;
        currentLine: string;
        j: integer;
    begin
        planScript := getScript(curPlan, 'SimSettlementsV2:Weapons:BuildingLevelPlan');
        curLevel := getScriptPropDefault(planScript, 'iRequiredLevel', -1);
        if(curLevel > 3) then begin
            AddMessage('WARNING: Plots with more than 3 levels aren''t supported in SS2. Skipping Level '+IntToStr(curLevel));
            exit;
        end;

        planItems := getScriptProp(planScript, 'StageItemSpawns');

        for j:=0 to ElementCount(planItems)-1 do begin
            curItem := ElementByIndex(planItems, j);

            currentLine := getCsvLineForSpawn(curItem, curLevel, true);

            list.add(currentLine);
        end;
    end;

    procedure saveBuildingPlanSpawnDataToFile(script: IInterface; targetFileName: string);
    var
        planList, curPlan: IInterface;
        list: TStringList;
        i, listLength: integer;

    begin
        // script := getScript(currentBlueprint, 'SimSettlementsV2:Weapons:BuildingPlan');

        list := TStringList.create;
        list.add(spawnsFileHeader);

        planList := getScriptProp(script, 'LevelPlansList');
        listLength := getFormListLength(planList);
        if(listLength = 0) then begin
            AddMessage('WARNING: this building plan has an empty LevelPlansList! '+FullPath(planList));
        end;
        for i:=0 to listLength-1 do begin
            curPlan := getFormListEntry(planList, i);
            exportBuildingPlanItems(curPlan, list);
        end;

        list.saveToFile(targetFileName);
        AddMessage('Wrote items to ' + targetFileName);
        list.free();
    end;



    function exportLevelSkinItems(levelSkin: IInterface; list: string): boolean;
    var
        itemSpawns, script, curSpawn, targetBP, targetBPscript: IInterface;
        curLevel, i: integer;
        currentLine: string;
        hasEntries: boolean;
    begin
        script := getScript(levelSkin, 'SimSettlementsV2:Weapons:BuildingLevelSkin');

        itemSpawns := getScriptProp(script, 'ReplaceStageItemSpawns');
        if(not assigned(itemSpawns)) then begin
            itemSpawns := getScriptProp(script, 'AdditionalStageItemSpawns');
        end;

        if(not assigned(itemSpawns)) then begin
            Result := false;
            exit;
        end;

        hasEntries := false;
        Result := false;

        targetBP := getScriptProp(script, 'TargetBuildingLevelPlan');
        if(not assigned(targetBP)) then begin
            curLevel := 1;
        end else begin
            targetBPscript := getScript(targetBP, 'SimSettlementsV2:Weapons:BuildingLevelPlan');
            curLevel := getScriptPropDefault(targetBPscript, 'iRequiredLevel', 1);
        end;


        for i:=0 to ElementCount(itemSpawns)-1 do begin
            curSpawn := ElementByIndex(itemSpawns, i);

            currentLine := getCsvLineForSpawn(curSpawn, curLevel, false);
            list.add(currentLine);
            hasEntries := true;
        end;

        if(hasEntries) then begin
            Result := true;
        end;
    end;

    procedure saveSkinSpawnDataToFile(script: IInterface; targetFileName: string);
    var
        levelSkins, curLvlSkin: IInterface;
        hasEntries : boolean;
        list: TStringList;
        i: integer;
    begin
        levelSkins := getScriptProp(script, 'LevelSkins');
        if(not assigned(levelSkins)) then begin
            AddMessage('No LevelSkins in this level?');
            exit;
        end;

        hasEntries := false;

        list := TStringList.create;

        list.add(spawnsFileHeader);

        for i:=0 to ElementCount(levelSkins)-1 do begin
            curLvlSkin := getObjectFromProperty(levelSkins, i);
            if(exportLevelSkinItems(curLvlSkin, list)) then begin
                hasEntries := true;
            end;
        end;

        if(hasEntries) then begin
            list.saveToFile(targetFileName);
            AddMessage('Wrote Items to ' + targetFileName);
        end else begin
            AddMessage('This skin seems to have no items');
        end;

        list.free();
    end;

    procedure saveSpawnDataToFile(targetFileName: string);
    var
        script: IInterface;
    begin
        script := getScript(currentBlueprint, 'SimSettlementsV2:Weapons:BuildingPlan');
        if(assigned(script)) then begin
            AddMessage('Exporting Spawns for '+EditorID(currentBlueprint));
            saveBuildingPlanSpawnDataToFile(script, targetFileName);
        end;

        script := getScript(currentBlueprint, 'SimSettlementsV2:Weapons:BuildingSkin');
        if(assigned(script)) then begin
            AddMessage('Exporting Spawns for '+EditorID(currentBlueprint));
            saveSkinSpawnDataToFile(script, targetFileName);
        end;
    end;

    procedure saveBuildingPlanModelDataToFile(targetFileName: string; script: IInterface);
    var
        buildMats, planList, curPlan, planScript, planModels, curModel: IInterface;
        i, j, listLength, curLevel: integer;
        currentLine: string;
        list: TStringList;
    begin
        // script := getScript(currentBlueprint, 'SimSettlementsV2:Weapons:BuildingPlan');
        list := TStringList.create;

        // prepare
        for i:=0 to 3 do begin
            list.add('');
        end;

        buildMats := getScriptProp(script, 'BuildingMaterialsOverride');
        planList := getScriptProp(script, 'LevelPlansList');


        if(assigned(buildMats)) then begin
            list[0] := EditorID(buildMats);
        end else begin
            list[0] := 'default';
        end;

        listLength := getFormListLength(planList);
        if(listLength = 0) then begin
            AddMessage('WARNING: this building plan has an empty LevelPlansList! '+FullPath(planList));
        end;

        for i:=0 to listLength-1 do begin
            currentLine := '';
            curPlan := getFormListEntry(planList, i);

            planScript := getScript(curPlan, 'SimSettlementsV2:Weapons:BuildingLevelPlan');

            curLevel := getScriptPropDefault(planScript, 'iRequiredLevel', -1);

            if(curLevel < 0) then begin
                AddMessage('ERROR: LevelPlan has no requiredLevel: '+EditorID(curPlan));
                continue;
            end;
            if(curLevel > 3) then begin
                AddMessage('WARNING: Plots with more than 3 levels aren''t supported in SS2. Skipping Level '+IntToStr(curLevel));
                continue;
            end;

            if(list[curLevel] <> '') then begin
                AddMessage('Multiple variants of the same levels are not supported.');
                AddMessage('Duplicate level: '+IntToStr(curLevel));
                continue;
            end;

            planModels := getScriptProp(planScript, 'StageModels');

            for j:=0 to ElementCount(planModels)-1 do begin
                curModel := PathLinksTo(ElementByIndex(planModels, j), 'Object v2\FormID');

                if(currentLine <> '') then begin
                    currentLine := currentLine + ',' + EditorID(curModel);
                end else begin
                    currentLine := EditorID(curModel);
                end;

                // AddMessage(FullPath(curModel));
            end;

            list[curLevel] := currentLine;
        end;


        list.saveToFile(targetFileName);
        AddMessage('Wrote models to ' + targetFileName);
        list.free();
    end;

    function exportLevelSkin(levelSkin: IInterface; list: TStringList): boolean;
    var
        ReplaceStageModel: IInterface;
        script: IInterface;
    begin
        script := getScript(levelSkin, 'SimSettlementsV2:Weapons:BuildingLevelSkin');
        ReplaceStageModel := getScriptProp(script, 'ReplaceStageModel');
        if(not assigned(ReplaceStageModel)) then begin
            Result := false;
            list.add('');
            exit;
        end;

        list.add(EditorID(ReplaceStageModel));
        Result := true;
    end;

    procedure saveSkinModelDataToFile(targetFileName: string; script: IInterface);
    var
        i: integer;
        levelSkins, curLvlSkin: IInterface;
        list: TStringList;
        hasEntries: boolean;
    begin
        levelSkins := getScriptProp(script, 'LevelSkins');
        if(not assigned(levelSkins)) then begin
            AddMessage('No LevelSkins in this level?');
            exit;
        end;

        hasEntries := false;

        list := TStringList.create;

        list.add(DisplayName(currentBlueprint));

        for i:=0 to ElementCount(levelSkins)-1 do begin
            curLvlSkin := getObjectFromProperty(levelSkins, i);
            if(exportLevelSkin(curLvlSkin, list)) then begin
                hasEntries := true;
            end;
            // AddMessage('FOO '+EditorID(curLvlSkin));
        end;

        if(hasEntries) then begin
            list.saveToFile(targetFileName);
            AddMessage('Wrote models to ' + targetFileName);
        end else begin
            AddMessage('This skin seems to have no models');
        end;

        list.free();
    end;


    procedure saveModelDataToFile(targetFileName: string);
    var
        script, buildMats, planList, curPlan, planScript, planModels, curModel: IInterface;
        i, j, listLength, curLevel: integer;
        currentLine: string;
        list: TStringList;
    begin
        script := getScript(currentBlueprint, 'SimSettlementsV2:Weapons:BuildingPlan');
        if(assigned(script)) then begin
            AddMessage('Exporting Models for '+EditorID(currentBlueprint));
            saveBuildingPlanModelDataToFile(targetFileName, script);
            exit;
        end;

        script := getScript(currentBlueprint, 'SimSettlementsV2:Weapons:BuildingSkin');
        if(assigned(script)) then begin
            AddMessage('Exporting Models for '+EditorID(currentBlueprint));
            saveSkinModelDataToFile(targetFileName, script);
            exit;
        end;
    end;

    procedure saveModelFile(Sender: TObject);
    var
        dialogResult: string;
    begin
        dialogResult := ShowSaveFileDialog('Save StageModels file as', 'CSV Files|*.csv|All Files|*.*');
        if(dialogResult = '') then begin
            exit;
        end;

        if(ExtractFileExt(dialogResult) = '') then begin
            dialogResult := dialogResult + '.csv';
        end;

        saveModelDataToFile(dialogResult);
    end;

    procedure saveItemFile(Sender: TObject);
    var
        dialogResult: string;
    begin
        dialogResult := ShowSaveFileDialog('Save StageItemSpawns file as', 'CSV Files|*.csv|All Files|*.*');
        if(dialogResult = '') then begin
            exit;
        end;

        if(ExtractFileExt(dialogResult) = '') then begin
            dialogResult := dialogResult + '.csv';
        end;

        saveSpawnDataToFile(dialogResult);
    end;


    procedure showDialog(e: IInterface);
    var
        script: IInterface;
        frm: TForm;
        resultCode: integer;
        btnClose, btnModels, btnItems: TButton;
    begin
        script := getScript(e, 'SimSettlementsV2:Weapons:BuildingPlan');
        if(not assigned(script)) then begin
            script := getScript(e, 'SimSettlementsV2:Weapons:BuildingSkin');
            if(not assigned(script)) then begin
                exit;
            end;
        end;

        currentBlueprint := e;

        frm := CreateDialog('Stage Data Export', 400, 170);

        CreateLabel(frm, 10, 10, EditorID(e));
        CreateLabel(frm, 10, 30, DisplayName(e));


        btnModels := CreateButton(frm, 40, 60, 'Export Models');
        btnItems  := CreateButton(frm, 220, 60, 'Export Spawns');
        btnModels.OnClick := saveModelFile;
        btnItems.OnClick := saveItemFile;

        btnClose  := CreateButton(frm, 170, 100, 'Close');
        btnClose.ModalResult := mrCancel;

        resultCode := frm.showModal();

        frm.free();

    end;

    // Called before processing
    // You can remove it if script doesn't require initialization code
    function Initialize: integer;
    begin
        Result := 0;
    end;

    // called for every record selected in xEdit
    function Process(e: IInterface): integer;
    begin
        Result := 0;

        // comment this out if you don't want those messages
        showDialog(e);

        // processing code goes here

    end;

    // Called after processing
    // You can remove it if script doesn't require finalization code
    function Finalize: integer;
    begin
        Result := 0;
    end;

end.