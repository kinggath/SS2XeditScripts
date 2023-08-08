{
  New script template, only shows processed records
  Assigning any nonzero value to Result will terminate script
}
unit userscript;
    uses dubhFunctions;
    
    var
        csvLines: TStringList;
        groupsToSearch: TStringList;
        selectedCell: IInterface;

    function getLayer(inFile: IInterface; layerName: string; checkMasters: boolean): IInterface;
    var
        myLayrGroup: IInterface;
        i: integer;
    begin
        myLayrGroup := AddGroupBySignature(inFile, 'LAYR');
        Result := MainRecordByEditorID(myLayrGroup, layerName);
        
        if(not assigned(Result)) then begin
            if (checkMasters) then begin
                for i:=0 to MasterCount(inFile)-1 do begin

                    Result := MainRecordByEditorID(GroupBySignature(MasterByIndex(inFile, i), 'LAYR'), layerName);
                    if (assigned(Result)) then begin
                        exit;
                    end;

                end;
            end;
            
            // create new


            Result := AddNewRecordToGroup(myLayrGroup, 'LAYR');
            setElementEditValues(Result, 'EDID', layerName);
            
        end;
    end;
    
    function findObjectByEdid(edid: String): IInterface;
    var
        iFiles, iSigs, j: integer;
        curGroup: IInterface;
        curFile: IInterface;
        curRecord: IInterface;
    begin
        curRecord := nil;
        for iFiles := 0 to FileCount-1 do begin
            curFile := FileByIndex(iFiles);
            
            if(assigned(curFile)) then begin 

                for iSigs:=0 to groupsToSearch.count-1 do begin
                    
                    curGroup := GroupBySignature(curFile, groupsToSearch[iSigs]);
                    if(assigned(curGroup)) then begin
                        curRecord := MainRecordByEditorID(curGroup, edid);
                        if(assigned(curRecord)) then begin
                            Result := curRecord;
                            exit;
                        end;
                        
                    end;
                    
                end;
            end;
        end;
    end;
    
    function createReference(cell: IInterface; baseForm: IInterface; posX, posY, posZ, rotX, rotY, rotZ, scale: Float): IInterface;
    var
        cellFile: IInterface;
        dataRec: IInterface;
    begin
        Result := Add(cell, 'REFR', true);
        cellFile := GetFile(cell);

        AddRequiredElementMasters(baseForm, cellFile, False);
        
        SetEditValue(AddElementByString(Result, 'NAME'), IntToHex(GetLoadOrderFormID(baseForm), 8));
        SetEditValue(AddElementByString(Result, 'XSCL'), FloatToStr(scale));
        
        seev(Result, 'DATA\Position\X', posX);
        seev(Result, 'DATA\Position\Y', posY);
        seev(Result, 'DATA\Position\Z', posZ);
        
        seev(Result, 'DATA\Rotation\X', rotX);
        seev(Result, 'DATA\Rotation\Y', rotY);
        seev(Result, 'DATA\Rotation\Z', rotZ);

    end;
    
    function fixEditorID(edid: string): string;
    var
        suffix: string;
        suffixInt: integer;
    begin
        Result := trim(edid);
        suffix := Copy(Result, Length(Result) - 2, 3);
        
        try 
            suffixInt := StrToInt(suffix);
        except
            // not an int, so just return the trimmed edid
            exit;
        end;
        
        // match 0xx numbers
        if(suffixInt < 100) then begin
            // strip off the suffix
            Result := Copy(Result, 1, Length(Result) - 3);
        end;
    end;

    procedure processLine(cell: IInterface; line: string; sPlanName: string);
    var
        fields: TStringList;
        stageNumStr, edid: string;
        curLayer, baseForm, refForm: IInterface;
    begin
        fields := TStringList.Create;

        fields.Delimiter := ',';
        fields.StrictDelimiter := TRUE;
        fields.DelimitedText := line;
        
        stageNumStr := fields[9];

        if (stageNumStr = '') then begin
            stageNumStr := '1'; //?
        end;
        
        // fields are like this:
        { 
        0 = Editor ID
        1 = Pos X
        2 = Pos Y
        3 = Pos Z
        4 = Rot X
        5 = Rot Y
        6 = Rot Z
        7 = Scale
        8 = sSpawnName
        9 = iStageNum
        10 = iStageEnd
        11 = iType
        12 = "ActorValue (enter the ID field, NOT the Hex ID)"
        13 = iValidActorValue
        }
        curLayer := getLayer(GetFile(cell), sPlanName + '_Stage_'+stageNumStr, true);
        
        edid := fixEditorID(fields[0]);

        baseForm := findObjectByEdid(edid);
        if(not assigned(baseForm)) then begin
            AddMessage('Could not find '+edid);
        end else begin

            refForm := createReference(
                cell, 
                baseForm,
                StrToFloat(fields[1]), 
                StrToFloat(fields[2]),
                StrToFloat(fields[3]),
                StrToFloat(fields[4]),
                StrToFloat(fields[5]),
                StrToFloat(fields[6]),
                StrToFloat(fields[7])
            );
            SetEditValue(AddElementByString(refForm, 'XLYR'), IntToHex(GetLoadOrderFormID(curLayer), 8));
             
        end;
        
        fields.free;
    end;

    // Called before processing
    // You can remove it if script doesn't require initialization code
    function Initialize: integer;
    begin
        Result := 0;
        
        
        groupsToSearch := TStringList.create;
         
        groupsToSearch.add('MISC'); 
        groupsToSearch.add('ALCH'); 
        groupsToSearch.add('AMMO'); 
        groupsToSearch.add('ARMO'); 
        groupsToSearch.add('BOOK'); 
        groupsToSearch.add('WEAP');
        groupsToSearch.add('CONT'); 
        groupsToSearch.add('DOOR'); 
        groupsToSearch.add('FLOR'); 
        groupsToSearch.add('FURN'); 
        groupsToSearch.add('LIGH'); 
        groupsToSearch.add('LVLI'); 
        groupsToSearch.add('LVLN'); 
        groupsToSearch.add('MSTT'); 
        groupsToSearch.add('NOTE');
        groupsToSearch.add('NPC_'); 
        groupsToSearch.add('STAT'); 
        groupsToSearch.add('SCOL'); 
        groupsToSearch.add('TERM'); 
        groupsToSearch.add('KEYM');
        groupsToSearch.add('ACTI'); 
        groupsToSearch.add('IDLM'); 
        groupsToSearch.add('SOUN');
        
        selectedCell := nil;
    end;

    // called for every record selected in xEdit
    function Process(e: IInterface): integer;
    begin
        Result := 0;

        if(signature(e) <> 'CELL') then exit;

        if(not assigned(selectedCell)) then begin
            selectedCell := e;
        end else begin
            AddMessage('Error: You must run this script on one cell exactly! More than one found!');
            Result := 1;
        end;
        
        //AddMessage('Processing: ' + FullPath(e));
        // start at 1 to skip the header
        

        // processing code goes here
        
    end;

    // Called after processing
    // You can remove it if script doesn't require finalization code
    function Finalize: integer;
    var
		fields: TStringList;
        i: integer;
        curLine, planName: string;
    begin
        Result := 0;
        
        if(not assigned(selectedCell)) then begin
            AddMessage('Error: You must run this script on one cell exactly! None found!');
            exit;
        end;
        
        csvLines := LoadFromCsv(false, false, false, '');

        if(csvLines.count <= 0) then begin
            Result := 1;
            AddMessage('No CSV file loaded!');
            exit;
        end;
		
		fields := TStringList.Create;

        fields.Delimiter := ',';
        fields.StrictDelimiter := TRUE;
        fields.DelimitedText := csvLines[0];
        
        planName := fields[0];
		
		planName := StringReplace(planName, ' ', '_', '');
		
		fields.free;
        
        for i:=1 to csvLines.count-1 do begin
            curLine := csvLines[i];
            processLine(selectedCell, curLine, planName);
        end;
        
    end;

end.