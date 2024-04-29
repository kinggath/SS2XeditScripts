{
    Translates a form to SS2. Run on a form.
}
unit TranslateForm;
    uses 'SS2\SS2Lib';
    const
        configFile = ScriptsPath + 'SS2_PlotConverter.cfg';
    var
        sourceFile, targetFile : IInterface;
        lastSelectedFileName, lastSelectedTargetFileName, newModName: string;
        showDialogForEachPlot: boolean;

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
                end else if(curKey = 'ShowPlotDialog') then begin
                    showDialogForEachPlot := StrToBool(curVal);
                end else if(curKey = 'LastFile') then begin
                    lastSelectedFileName := curVal;
                end else if(curKey = 'SourceFile') then begin
                    lastSelectedTargetFileName := curVal;
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
        lines.add('ShowPlotDialog='+BoolToStr(showDialogForEachPlot));
        lines.add('LastFile='+GetFileName(targetFile));
        if(assigned(sourceFile)) then begin
            lines.add('SourceFile='+GetFileName(sourceFile));
        end;

        lines.saveToFile(configFile);
        lines.free();
    end;

    {
        Shows the main config dialog, where you can select the target file and the prefixes
    }
    function showInitialConfigDialog(): boolean;
    var
        frm: TForm;
        btnOk, btnCancel: TButton;
        inputNewPrefix, inputOldPrefix: TEdit;
        resultCode, i, curIndex, selectedIndex: integer;
        selectSourceFile, selectTargetFile: TComboBox;

        s: string;
    begin
        loadConfig();

        //AddMessage('A '+newModName+', '+newFormPrefix+', '+oldFormPrefix);

        Result := false;
        frm := CreateDialog('Translate Form Manually', 370, 230);

        //CreateLabel(frm, 210, 13, '(optional)');
        CreateLabel(frm, 10, 7, 'Source file');
        selectSourceFile := CreateComboBox(frm, 80, 5, 240, nil);
        selectSourceFile.Style := csDropDownList;
        // selectSourceFile.Items.Add('-- CREATE NEW FILE --');
        // selectSourceFile.ItemIndex := 0;
        selectedIndex := -1;
        for i := 0 to FileCount - 1 do begin
            s := GetFileName(FileByIndex(i));
            if (Pos(s, readOnlyFiles) > 0) then Continue;

            curIndex := selectSourceFile.Items.Add(s);

            if(s = lastSelectedTargetFileName) then begin
                selectedIndex := curIndex;
            end;

        end;
        selectSourceFile.ItemIndex := selectedIndex;


        CreateLabel(frm, 10, 37, 'Target file');
        selectTargetFile := CreateComboBox(frm, 80, 35, 240, nil);
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


        CreateLabel(frm, 10, 73, 'New prefix');
        inputNewPrefix  := CreateInput(frm, 80, 70, newFormPrefix);
        CreateLabel(frm, 210, 73, '(required)');

        CreateLabel(frm, 10, 93, 'Old prefix');
        inputOldPrefix  := CreateInput(frm, 80, 90, oldFormPrefix);
        CreateLabel(frm, 210, 93, '(optional)');
        CreateLabel(frm, 10, 113, 'The new prefix will be used for newly-generated forms.'+STRING_LINE_BREAK+'If old prefix is given, it will be replace by new prefix.');

        btnOk := CreateButton(frm, 50, 170, 'Start');
        btnOk.ModalResult := mrYes;
        btnOk.Default := true;

        btnCancel := CreateButton(frm, 250, 170, 'Cancel');
        btnCancel.ModalResult := mrCancel;

        resultCode := frm.ShowModal;

        if(resultCode = mrYes) then begin
            newFormPrefix := inputNewPrefix.text;
            oldFormPrefix := inputOldPrefix.text;

            globalNewFormPrefix := newFormPrefix;

            // newModName := inputModName.text;
            // globalAddonName := newModName;

            if(newFormPrefix = '') then begin
                AddMessage('You must enter a new prefix');
                exit;
            end;

            if(selectSourceFile.ItemIndex <> -1) then begin
                sourceFile := FindFile(selectSourceFile.Items[selectSourceFile.ItemIndex]);
            end else begin
                Result := false;
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



            if(assigned(targetFile)) and assigned(sourceFile) then begin
                saveConfig();
                Result := true;
            end;
        end;

        frm.free();
    end;

    // Called before processing
    // You can remove it if script doesn't require initialization code
    function Initialize: integer;
    begin
        initSS2Lib();
        if(not showInitialConfigDialog()) then begin
            Result := 1;
            exit;
        end;

        Result := 0;
    end;

    // called for every record selected in xEdit
    function Process(e: IInterface): integer;
    var
        newEdid: string;
        newForm, curFile: IInterface;
    begin
        Result := 0;

        AddMessage('Translating: ' + FullPath(e));

        // newEdid :=
        curFile := GetFile(e);
        if(FilesEqual(curFile, targetFile)) then begin
            findFormIds(e, sourceFile, targetFile);
        end else begin
            newForm := translateFormToFile(e, curFile, targetFile);
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
    end;

end.