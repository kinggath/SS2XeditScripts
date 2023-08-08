{
    Run on PBP COBJs
}
unit userscript;
    uses praUtil;

    var
        ss2master: IInterface;
        resultList: TStringList;
        targetFilePath: string;

    // Called before processing
    // You can remove it if script doesn't require initialization code
    function Initialize: integer;
    begin
        Result := 0;

        ss2master := FindFile('SS2.esm');
        if(not assigned(ss2master)) then begin
            AddMessage('Error, SS2.esm not found');
            Result := 1;
            exit;
        end;
        
        targetFilePath := ShowSaveFileDialog('Save CSV as', 'CSV|*.csv');
        if(targetFilePath = '') then begin
            AddMessage('Cancelled');
            exit;
        end;
        
        if(not strEndsWith(targetFilePath, '.csv')) then begin
            targetFilePath := targetFilePath+'.csv';
        end;
        
        resultList := TStringList.create;
        resultList.add('Old EDID,new EDID,Category KW');
    end;

    function getSS2VersionEdid(ss1Edid: string): string;
    var
        ss2Edid: string;
        newVersion: IInterface;
    begin

        newVersion := FindObjectInFileByEdid(ss2Master, ss1Edid);
        if(assigned(newVersion)) then begin
            Result := ss1Edid;
            exit
        end;


        ss2Edid := StringReplace(ss1Edid, 'kgSIM_', 'SS2_', [rfIgnoreCase]);
        newVersion := FindObjectInFileByEdid(ss2Master, ss2Edid);


        if(assigned(newVersion)) then begin
            Result := ss2Edid;
            exit
        end;

        Result := 'MISSING';
    end;


    // called for every record selected in xEdit
    function Process(e: IInterface): integer;
    var
        ss1Edid: string;
        cnam, fnamList, fnamKw: IInterface;
    begin
        Result := 0;

        if(Signature(e) <> 'COBJ') then begin
            exit;
        end;

        AddMessage('Processing: ' + FullPath(e));
        cnam := PathLinksTo(e, 'CNAM');
        ss1Edid := EditorID(cnam);

        fnamList := ElementByPath(e, 'FNAM');

        if(ElementCount(fnamList) = 0) then begin
            AddMessage('no fnam here? '+EditorID(e));
            exit;
        end;

        fnamKw := LinksTo(ElementByIndex(fnamList, 0));
        
        resultList.add(ss1Edid+','+getSS2VersionEdid(ss1Edid)+','+EditorID(fnamKw));

        // AddMessage('CNAM '+ss1Edid+', '+EditorID(fnamKw)+', '+getSS2VersionEdid(EditorID(cnam)));

    end;

    // Called after processing
    // You can remove it if script doesn't require finalization code
    function Finalize: integer;
    begin
        Result := 0;
        AddMessage('Writing target file');
        resultList.saveToFile(targetFilePath);
        resultList.free();
    end;

end.