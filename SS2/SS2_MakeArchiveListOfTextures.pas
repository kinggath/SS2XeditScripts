{
    Run on anything within SS2.esm
}
unit ListFuz;
    uses praUtil;

    var
        targetFile: IInterface;

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

        targetFile := GetFile(e);
    end;

    function ExtractFileBasename(filename: string): string;
    var
        curExt: string;
    begin
        curExt := ExtractFileExt(filename);

        Result := copy(filename, 0, length(filename)-length(curExt));
    end;

    // Called after processing
    // You can remove it if script doesn't require finalization code
    function Finalize: integer;
    var
        baseName, mainba2, curFile, targetFileName: string;
        fuzList, ba2content: TStringList;
        i: integer;
        texList: TJsonArray;
    begin
        Result := 0;
        if(not assigned(targetFile)) then exit;

        baseName := ExtractFileBasename(GetFileName(targetFile));
        mainba2 := DataPath+basename + ' - Textures.ba2';

        if(not fileExists(mainba2)) then begin
            AddMessage('Could not find '+mainba2);
            exit;
        end;

        targetFileName := ShowSaveFileDialog('Save JSON to', 'All Files|*.*');
        if (targetFileName = '') then begin
            AddMessage('Cancelled');
            exit;
        end;

        texList := TJsonArray.create;
        fuzList := TStringList.create;
{
        fuzList.CaseSensitive := false;
        fuzList.Duplicates := dupIgnore;
}
        ba2content := TStringList.create;
        ba2content.CaseSensitive := false;
        ba2content.Duplicates := dupIgnore;

        ResourceList(mainba2, ba2content);

        for i:=0 to ba2content.count-1 do begin
            curFile := ba2content[i];

            if(strEndsWith(LowerCase(curFile), '.dds')) then begin
                //fuzList.add(curFile);
                texList.add('Data\'+curFile);
            end;
        end;

        fuzList.add(texList.toString());

        // AddMessage('Saving '+IntToStr(fuzList.count)+' entries');
        // fuzList.sort();
        fuzList.saveToFile(targetFileName);

    end;

end.