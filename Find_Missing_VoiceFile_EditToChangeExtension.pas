{
   Searches for extToFind and reports if an equivalent file of extToReport is missing.
   Run on header.
}
unit userscript;
    uses praUtil;

    const
        pathToCheck = 'Sound\Voice\SS2.esm\SS2_VT_MALA';
	extToFind = '.fuz';
        extToReport = '.wav';

    var
        resultList: TStringList;

    procedure checkFile(filePath: string);
    var
        searchPath: string;
    begin
        //resultList
        searchPath := StringReplace(filePath, extToFind, extToReport, 0);

        if(not FileExists(DataPath+searchPath)) then begin
            AddMessage('MISSING '+searchPath);
            resultList.add(searchPath);
        end;
    end;

    function stripSlash(path: string): string;
    begin
        Result := path;

        if(SameText(copy(path, length(path), 1), '\')) then begin
            Result := copy(path, 0, length(path)-1);
        end;
    end;

    function processResourceDirectoryRecursive(dir: string): boolean;
    var
        curFullPath: string;
        searchResult : TSearchRec;
        curFile: string;
    begin
        curFullPath := DataPath + stripSlash(dir);

        Result := false;

        if(not DirectoryExists(curFullPath)) then begin
            exit;
        end;

        if FindFirst(curFullPath+'\*', faAnyFile, searchResult) = 0 then begin
            repeat
                // ignore . and ..
                if(searchResult.Name <> '.') and (searchResult.Name <> '..') then begin
                    curFile := LowerCase(stripSlash(dir)+'\'+searchResult.Name);

                    if((searchResult.attr and faDirectory) = faDirectory) then begin
                        // dir
                        if(processResourceDirectoryRecursive(curFile)) then begin
                            Result := true;
                        end;
                    end else begin
                        if(strEndsWith(curFile, extToFind)) then begin
                            checkFile(curFile);
                        end;
                    end;
                end;
            until FindNext(searchResult) <> 0;

            // Must free up resources used by these successful finds
            FindClose(searchResult);
        end;


    end;


    // called for every record selected in xEdit
    function Process(e: IInterface): integer;
    begin
        Result := 0;

        // comment this out if you don't want those messages
        // AddMessage('Processing: ' + FullPath(e));

        // processing code goes here
    end;

    // Called after processing
    // You can remove it if script doesn't require finalization code
    function Finalize: integer;
    var
        saveTo: string;
    begin
        Result := 0;
        
        saveTo := ShowSaveFileDialog('Save list to', '');
        if(saveTo = '') then begin
            Result := 1;
            exit;
        end;

        resultList := TStringList.create();

        // do stuff
        processResourceDirectoryRecursive(pathToCheck);


        resultList.saveToFile(saveTo);

        resultList.free();
    end;

end.
