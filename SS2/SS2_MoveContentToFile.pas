{
    This should copy SS2 content to a new file
}
unit MoveContentToFile;
    uses 'SS2\SS2Lib';
    const
        configFile = ProgramPath + 'Edit Scripts\SS2_MoveContentToFile.cfg';
        flidPrefix = 'SS2_FLID_';
    var
        sourceFile, targetFile : IInterface;
        lastSelectedFileName, newModName: string;
        typeKeywords: TStringList;
        settingRegisterContent, settingSetupStacking: boolean;
        selectedTypeKeyword: IInterface;

    procedure loadTypes();
    var
        ss2file, kwGrp, curKw: IInterface;
        i: integer;
        curEdid, curName: string;
    begin
        typeKeywords := TStringList.create;
        typeKeywords.sorted := true;

        ss2file := FindFile('SS2.esm');
        kwGrp := GroupBySignature(ss2file, 'KYWD');
        for i:=0 to ElementCount(kwGrp)-1 do begin
            curKw := ElementByIndex(kwGrp, i);
            curEdid := EditorID(curKw);

            if(strStartsWith(curEdid, flidPrefix)) then begin
                curName := StringReplace(curEdid, flidPrefix, '', 0);
                typeKeywords.addObject(curName, curKw);
            end;
        end;
    end;

    function findContentKeyword(e: IInterface): IInterface;
    var
        i: integer;
        curRef, firstEntry: IInterface;
    begin
        Result := nil;
        for i:=0 to ReferencedByCount(e)-1 do begin
            curRef := ReferencedByIndex(e, i);
            if (Signature(curRef) = 'FLST') then begin
                firstEntry := getFormListEntry(curRef, 0);
                if(Signature(firstEntry) = 'KYWD') then begin
                    if(strStartsWith(EditorID(firstEntry), flidPrefix)) then begin
                        Result := firstEntry;
                        exit;
                    end;
                end;
            end;
        end;
    end;

// SS2_FLID_
    procedure loadConfig();
    var
        i, j, breakPos: integer;
        curLine, curKey, curVal: string;
        lines : TStringList;
    begin
        // default
        newFormPrefix := 'addon_';
        oldFormPrefix := '';
        lastSelectedFileName := '';

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

                if(curKey = 'ModName') then begin
                    newModName := curVal;
                end else if(curKey = 'NewPrefix') then begin
                    newFormPrefix := curVal;
                end else if(curKey = 'OldPrefix') then begin
                    oldFormPrefix := curVal;
                end else if(curKey = 'LastFile') then begin
                    lastSelectedFileName := curVal;
                end else if(curKey = 'RegisterContent') then begin
                    settingRegisterContent := StrToBool(curVal);
                end else if(curKey = 'SetupStacking') then begin
                    settingSetupStacking := StrToBool(curVal);
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
        lines.add('ModName='+newModName);
        lines.add('NewPrefix='+newFormPrefix);
        lines.add('OldPrefix='+oldFormPrefix);

        lines.add('LastFile='+GetFileName(targetFile));
        lines.add('RegisterContent='+BoolToStr(settingRegisterContent));
        lines.add('SetupStacking='+BoolToStr(settingSetupStacking));


        lines.saveToFile(configFile);
        lines.free();
    end;

    procedure contentTypeChangeHandler(sender: TObject);
    var
        selectContentType: TComboBox;
        registerContent: TCheckBox;

    begin
        selectContentType := TComboBox(sender);
        registerContent := selectContentType.parent.findComponent('cbRegisterContent');
        if(selectContentType.ItemIndex < 0) then begin
            registerContent.enabled := false;
            registerContent.checked := false;
        end else begin
            registerContent.enabled := true;
            registerContent.checked := settingRegisterContent;
        end;
    end;

    procedure setDropdownByForm(dropdown: TComboBox; e: IInterface);
    var
        i: integer;
        curElem: IInterface;
    begin
        for i:=0 to dropdown.Items.count-1 do begin
            curElem := ObjectToElement(dropdown.Items.Objects[i]);
            if(Equals(curElem, e)) then begin
                dropdown.ItemIndex := i;
                exit;
            end;
        end;
    end;

    {
        Shows the main config dialog, where you can select the target file and the prefixes
    }
    function showInitialConfigDialog(elem: IInterface): boolean;
    var
        frm: TForm;
        btnOk, btnCancel: TButton;
        inputNewPrefix, inputOldPrefix: TEdit;
        resultCode, i, curIndex, selectedIndex: integer;
        selectContentType, selectTargetFile: TComboBox;
        yOffset: integer;
        s: string;
        prefixGroup, registerGroup: TGroupBox;
        registerContent, setupStacking: TCheckBox;
        contentKeyword: IInterface;
    begin
        loadConfig();

        Result := false;
        frm := CreateDialog('Move SS2 content', 500, 300);

        yOffset := 10;
        CreateLabel(frm, 10, yOffset+7, 'Moving '+EditorID(elem));
        yOffset := 30;

        CreateLabel(frm, 10, yOffset+7, 'Target file');
        selectTargetFile := CreateComboBox(frm, 80, yOffset+5, 240, nil);
        selectTargetFile.Style := csDropDownList;
        selectTargetFile.Items.Add('-- CREATE NEW FILE --');
        // selectTargetFile.ItemIndex := 0;
        selectedIndex := 0;
        for i := 0 to FileCount - 1 do begin
            s := GetFileName(FileByIndex(i));
            if (Pos(s, readOnlyFiles) > 0) then Continue;

            curIndex := selectTargetFile.Items.Add(s);
            // AddMessage('Fu '+s+', '+lastSelectedFileName);
            if(s = lastSelectedFileName) then begin
                selectedIndex := curIndex;
            end;

        end;
        selectTargetFile.ItemIndex := selectedIndex;

        yOffset := yOffset + 30;

        prefixGroup := CreateGroup(frm, 10, yOffset, 485, 70, 'Prefix');


        CreateLabel(prefixGroup, 10, 18, 'New prefix');
        inputNewPrefix  := CreateInput(prefixGroup, 80, 15, newFormPrefix);
        //CreateLabel(frm, 210, 73, '(optional)');

        CreateLabel(prefixGroup, 250, 18, 'Old prefix');
        inputOldPrefix  := CreateInput(prefixGroup, 320, 15, oldFormPrefix);
        //CreateLabel(frm, 210, 93, '(optional)');
        CreateLabel(prefixGroup, 10, 45, 'The new prefix will be used for newly-generated forms.'+STRING_LINE_BREAK+'If old prefix is given, it will be replace by new prefix.');

        yOffset := yOffset + 90;

        registerGroup := CreateGroup(frm, 10, yOffset, 485, 70, 'Register Content');
        CreateLabel(registerGroup, 10, 18, 'Content Type');
        selectContentType := CreateComboBox(registerGroup, 80, 15, 340, typeKeywords);
        selectContentType.Style := csDropDownList;
        selectContentType.Name := 'selectContentType';
        selectContentType.onChange := contentTypeChangeHandler;

        registerContent := CreateCheckbox(registerGroup, 60, 45, 'Register Content');
        registerContent.Name := 'cbRegisterContent';
        registerContent.Checked := settingRegisterContent;

        setupStacking := CreateCheckbox(registerGroup, 270, 45, 'Setup Stacking');
        setupStacking.Checked := settingSetupStacking;


        contentKeyword := findContentKeyword(elem);
        if(assigned(contentKeyword)) then begin
            setDropdownByForm(selectContentType, contentKeyword);
        end;

        //settingRegisterContent, settingSetupStacking: boolean;
        contentTypeChangeHandler(selectContentType);


        yOffset := yOffset + 90;
        btnOk := CreateButton(frm, 50, yOffset, 'Start');
        btnOk.ModalResult := mrYes;
        btnOk.Default := true;

        btnCancel := CreateButton(frm, 250, yOffset, 'Cancel');
        btnCancel.ModalResult := mrCancel;

        resultCode := frm.ShowModal;

        if(resultCode = mrYes) then begin
            newFormPrefix := inputNewPrefix.text;
            oldFormPrefix := inputOldPrefix.text;

            globalNewFormPrefix := newFormPrefix;
            selectedTypeKeyword := nil;

            if(selectContentType.ItemIndex >= 0) then begin
                settingRegisterContent := registerContent.Checked;
                selectedTypeKeyword := ObjectToElement(selectContentType.Items.Objects[selectContentType.ItemIndex]);
            end;

            settingSetupStacking   := setupStacking.Checked;

            // newModName := inputModName.text;
            // globalAddonName := newModName;


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
                        targetFile := FileSelect('Select another file');
                    end;
                end;
            end;



            if(assigned(targetFile)) then begin
                saveConfig();
                Result := true;
            end;
        end;

        frm.free();
    end;

    procedure doSetupStacking(e: IInterface);
    var
        script: IInterface;
        curModel, stageList, stageModels, LevelSkins: IInterface;
        i: integer;
    begin
        // only works on plots and skins
        script := getScript(e, 'SimSettlementsV2:Weapons:BuildingPlan');
        if(assigned(script)) then begin
            curModel := getScriptProp(script, 'BuildingMaterialsOverride');
            if(assigned(curModel)) then begin
                if(IsSameFile(getFile(curModel), targetFile)) then begin
                    addToStackEnabledList(targetFile, curModel);
                end;
            end;
            stageList := getScriptProp(script, 'LevelPlansList');
            if(assigned(stageList)) then begin
                for i:=0 to GetFormListLength(stageList) do begin
                    curModel := getFormListEntry(stageList, i);
                    doSetupStacking(curModel);
                end;
            end;
            exit;
        end;

        script := getScript(e, 'SimSettlementsV2:Weapons:BuildingLevelPlan');
        if (assigned(script)) then begin
            StageModels := getScriptProp(script, 'StageModels');
            for i:=0 to ElementCount(StageModels)-1 do begin
                curModel := getObjectFromProperty(StageModels, i);
                addToStackEnabledList(targetFile, curModel);
            end;
            exit;
        end;


        script := getScript(e, 'SimSettlementsV2:Weapons:BuildingSkin');
        if (assigned(script)) then begin
            LevelSkins := getScriptProp(script, 'LevelSkins');
            for i:=0 to ElementCount(LevelSkins)-1 do begin
                curModel := getObjectFromProperty(LevelSkins, i);
                doSetupStacking(curModel);
            end;
            exit;
        end;

        script := getScript(e, 'SimSettlementsV2:Weapons:BuildingLevelSkin');
        if (assigned(script)) then begin
            curModel := getScriptProp(script, 'ReplaceStageModel');
            if(assigned(curModel)) then begin
                addToStackEnabledList(targetFile, curModel);
            end;
        end;
    end;

    procedure postProcessForm(e: IInterface);
    begin
        //settingRegisterContent, settingSetupStacking: boolean;
        //selectedTypeKeyword: IInterface;
        if(settingRegisterContent) and (assigned(selectedTypeKeyword)) then begin
            registerAddonContent(targetFile, e, selectedTypeKeyword);
        end;

        if(settingSetupStacking) then begin
            doSetupStacking(e);
        end;
    end;

    // Called before processing
    // You can remove it if script doesn't require initialization code
    function Initialize: integer;
    begin
        initSS2Lib();

        loadTypes();
        Result := 0;
    end;

    // called for every record selected in xEdit
    function Process(e: IInterface): integer;
    var
        newEdid: string;
        newForm, curFile: IInterface;
    begin
        Result := 0;

        //AddMessage('Translating: ' + FullPath(e));

        // newEdid :=
        curFile := GetFile(e);
        if(not FilesEqual(curFile, targetFile)) then begin
            sourceFile := curFile;
            if(not showInitialConfigDialog(e)) then begin
                Result := 1;
                exit;
            end;
            newForm := translateFormToFile(e, curFile, targetFile);
            postProcessForm(newForm);
        end;
        // comment this out if you don't want those messages

        // processing code goes here

    end;

    // Called after processing
    // You can remove it if script doesn't require finalization code
    function Finalize: integer;
    begin
        Result := 0;

        if(assigned(targetFile)) then begin
            CleanMasters(targetFile);
        end;

        cleanupSS2Lib();
        typeKeywords.free();
    end;

end.