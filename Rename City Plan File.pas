{
    Run on city plan layer.
    Put in old and new filenames.
}
unit RenameCityPlanFile;
    uses praUtil;
    
    var
        oldFilename, newFilename: string;

    // Called before processing
    // You can remove it if script doesn't require initialization code
    function Initialize: integer;
    var
        frm: TForm;
        btnOk, btnCancel: TButton;
        resultCode: integer;
        inputOld, inputNew: TEdit;
    begin
        Result := 0;
        
        frm := CreateDialog('Rename City Plan File', 500, 200);
        
        CreateLabel(frm, 10, 6, 'Old Filename:');
        inputOld := CreateInput(frm, 10, 24, '');
        inputOld.width := 470;
        
        CreateLabel(frm, 10, 56, 'New Filename:');
        inputNew := CreateInput(frm, 10, 74, '');
        inputNew.width := 470;
        
        
        btnOk := CreateButton(frm, 100, 130, 'Start');
        btnOk.ModalResult := mrYes;
        btnOk.Default := true;

        btnCancel := CreateButton(frm, 300, 130, 'Cancel');
        btnCancel.ModalResult := mrCancel;
        resultCode := frm.ShowModal();
        
        if(resultCode <> mrYes) then begin
            AddMessage('cancelled');
            Result := 1;
            exit;
        end;
        
        oldFilename := LowerCase(Trim(inputOld.Text));
        newFilename := Trim(inputNew.Text);
        
        if (oldFilename = '') then begin
            AddMessage('Old filename cannot be empty!');
            Result := 1;
        end;
        
        if (newFilename = '') then begin
            AddMessage('New filename cannot be empty!');
            Result := 1;
        end;
        
        //oldFilename, newFilename
    end;

    // called for every record selected in xEdit
    function Process(e: IInterface): integer;
    var
        layerScript, itemArray, curStruct: IInterface;
        numReplacements, i: integer;
        curOldFilename: string;
    begin
        Result := 0;
        
        if(Signature(e) <> 'MISC') then exit;

        layerScript := getScript(e, 'SimSettlements:CityPlanLayer');
        if(not assigned(layerScript)) then exit;
        
        itemArray := getScriptProp(layerScript, 'Items');
        if(not assigned(itemArray)) then exit;
        
        numReplacements := 0;
        AddMessage('Processing '+EditorID(e));
        
        for i:=0 to ElementCount(itemArray)-1 do begin
            curStruct := ElementByIndex(itemArray, i);

            curOldFilename := LowerCase(getStructMember(curStruct, 'FormPlugin'));
            
            if(curOldFilename = oldFilename) then begin
                numReplacements := numReplacements+1;
                setStructMember(curStruct, 'FormPlugin', newFilename);
            end;
        end;
        
        AddMessage('Done '+IntToStr(numReplacements)+' replacements.');
    end;
end.