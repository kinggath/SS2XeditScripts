{
    Run on any number of HQ Layouts
}
unit OffsetCellRefs;
    uses 'SS2\praUtil';

    var
        targetCell, targetFile: IInterface;
        offsetX, offsetY, offsetZ: float;

        // stats
        numRefs, numLayouts: integer;

    function getElementToEdit(e: IInterface): IInterface;
    var
        elemFile: IInterface;
    begin
        elemFile := GetFile(e);
        if(isSameFile(elemFile, targetFile)) then begin
            Result := e;
            exit;
        end;

        // addRequiredMastersSilent(e, targetFile);
        Result := createElementOverride(e, targetFile);
    end;
    
    procedure processSpawnArray(arr: IInterface);
    var
        i, cnt: integer;
        curStruct: IInterface;
        curX, curY, curZ: float;
    begin
        // dumpElem(arr);
        cnt := getPropertyArrayLength(arr);
        for i:= 0 to cnt-1 do begin
            curStruct := ElementByIndex(arr, i);
            
           // fooobar();
            curX := getStructMemberDefault(curStruct, 'fPosX', 0.0) + offsetX;
            curY := getStructMemberDefault(curStruct, 'fPosY', 0.0) + offsetY;
            curZ := getStructMemberDefault(curStruct, 'fPosZ', 0.0) + offsetZ;
            
            setStructMemberDefault(curStruct, 'fPosX', curX, 0.0);
            setStructMemberDefault(curStruct, 'fPosY', curY, 0.0);
            setStructMemberDefault(curStruct, 'fPosZ', curZ, 0.0);
            
            numRefs := numRefs + 1;
        end;
    end;

    procedure processLayout(layout: IInterface);
    var
        layoutToEdit,layoutScript: IInterface;
    begin
        layoutToEdit := getElementToEdit(layout);
        
        
        layoutScript := getScript(layoutToEdit, 'SimSettlementsV2:Weapons:CityPlanLayout');
        BeginUpdate(layoutScript);
        
        AddMessage('Processing Layout '+Name(layout));
        
        // NonResourceObjects array of struct
        // WorkshopResources array of struct
        
        processSpawnArray(getScriptProp(layoutScript, 'NonResourceObjects'));
        processSpawnArray(getScriptProp(layoutScript, 'WorkshopResources'));
        EndUpdate(layoutScript);
        
        numLayouts := numLayouts + 1;
    end;
    

    function showGui(curTargetFile: IInterface): boolean;
    var
        frm: TForm;
        grp: TGroupBox;
        yOffset: integer;
        inputX, inputY, inputZ: TEdit;

        btnOk, btnCancel: TButton;
        resultCode: cardinal;

        targetFileBox: TComboBox;
        newFileName: string;
    begin
        Result := false;
        frm := CreateDialog('Offset HQ Layouts', 500, 300);

        //CreateLabel(frm, 10, 10, 'Offset Amounts:');
        grp := CreateGroup(frm, 10, 10, 480, 100, 'Offset Amounts');
        yOffset := 8;
        CreateLabel(grp, 20, 16+yOffset, 'X:');
        inputX := CreateInput(grp, 40, 14+yOffset, '0.0');
        inputX.Width := 400;

        yOffset := yOffset + 24;
        CreateLabel(grp, 20, 16+yOffset, 'Y:');
        inputY := CreateInput(grp, 40, 14+yOffset, '0.0');
        inputY.Width := 400;

        yOffset := yOffset + 24;
        CreateLabel(grp, 20, 16+yOffset, 'Z:');
        inputZ := CreateInput(grp, 40, 14+yOffset, '0.0');
        inputZ.Width := 400;

        yOffset := 140;
        CreateLabel(frm, 40, yOffset+2, 'Target File:');
        targetFileBox := CreateFileSelectDropdown(frm, 120, yOffset, 200, curTargetFile, true);
        yOffset := 180;

        btnOk := CreateButton(frm, 80, yOffset, '    OK    ');
        btnCancel := CreateButton(frm, 280, yOffset, '  Cancel  ');

        btnCancel.ModalResult := mrCancel;
        btnOk.ModalResult := mrOk;

        resultCode := frm.showModal();
        if (resultCode <> mrOk) then begin
            frm.free();
            exit;
        end;

        offsetX := StrToFloat(inputX.text);
        offsetY := StrToFloat(inputY.text);
        offsetZ := StrToFloat(inputZ.text);

        if(targetFileBox.ItemIndex = 0) then begin
            // add new file

            if(not InputQuery('Offset HQ Layouts', 'Enter New File Name (with or without extension)', newFileName)) then begin
                frm.free();
                exit;
            end;
            newFileName := trim(newFileName);
            if(newFileName = '') then begin
                frm.free();
                exit;
            end;

            if (not strEndsWithCI(newFileName, '.esp')) and (not strEndsWithCI(newFileName, '.esl')) and (not strEndsWithCI(newFileName, '.esm')) then begin
                newFileName := newFileName+'.esp';
            end;

            targetFile := AddNewFileName(newFileName);
            if(not assigned(targetFile)) then begin
                frm.free();
                exit;
            end;
        end else begin
            newFileName := targetFileBox.Items[targetFileBox.ItemIndex];
            targetFile := FindFile(newFileName);

            if(not assigned(targetFile)) then begin
                AddMessage('ERROR');
                frm.free();
                exit;
            end;
        end;

        frm.free();
        Result := true;
    end;

    // Called before processing
    // You can remove it if script doesn't require initialization code
    function Initialize: integer;
    begin
        Result := 0;



        numRefs := 0;
        numLayouts := 0;

    end;

    // called for every record selected in xEdit
    function Process(e: IInterface): integer;
    var
        layoutScript: IInterface;
        curSig: string;
        
    begin
        Result := 0;

        layoutScript := getScript(e, 'SimSettlementsV2:Weapons:CityPlanLayout');

        if(not assigned(layoutScript)) then exit;
        // comment this out if you don't want those messages
        // AddMessage('Processing: ' + FullPath(e));


        if (not assigned(targetFile)) then begin


            if(not showGui(GetFile(e))) then begin
                Result := 1;
                exit;
            end;

        end;
        // otherwise continue and process this ref
        
        processLayout(e);

    end;

    // Called after processing
    // You can remove it if script doesn't require finalization code
    function Finalize: integer;
    begin
        Result := 0;

        AddMessage('Processed '+IntToStr(numRefs)+' spawns across '+IntToStr(numLayouts)+' layouts');
 
        {numNavmeshes := 0;
        numRefs := 0;

        // new bounds
        minX := 0;
        minY := 0;
        minZ := 0;
        maxX := 0;
        maxY := 0;
        maxZ := 0;}
    end;

end.