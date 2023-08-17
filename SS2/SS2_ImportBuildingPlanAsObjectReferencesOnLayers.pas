{
    Run on a cell, select spawns CSV
}
unit ImportCsvToCell;
    uses 'SS2\praUtil';

    var
        csvLines: TStringList;
        groupsToSearch: TStringList;
        selectedCell: IInterface;

    function AddGroupBySignature(const f: IwbFile; const s: String): IInterface;
    begin
        Result := GroupBySignature(f, s);
        if not Assigned(Result) then
            Result := Add(f, s, True);
    end;

    function getLayer(inFile: IInterface; layerName: string; checkMasters: boolean): IInterface;
    var
        curMaster, myLayrGroup, foundLayer: IInterface;
        i: integer;
    begin
        myLayrGroup := AddGroupBySignature(inFile, 'LAYR');
        foundLayer := MainRecordByEditorID(myLayrGroup, layerName);
        Result := nil;

        if(assigned(foundLayer)) then begin
            Result := foundLayer;
            exit;
        end;


        if (checkMasters) then begin
            for i:=0 to MasterCount(inFile)-1 do begin

                curMaster := MasterByIndex(inFile, i);

                foundLayer := MainRecordByEditorID(GroupBySignature(curMaster, 'LAYR'), layerName);
                if (assigned(foundLayer)) then begin
                    Result := foundLayer;
                    exit;
                end;

            end;
        end;

        // create new
        foundLayer := Add(myLayrGroup, 'LAYR', true);//ensurePath(myLayrGroup, 'LAYR');
        setElementEditValues(foundLayer, 'EDID', layerName);


        Result := foundLayer;
    end;

    function getSS2VersionEdid(ss1Edid: string): string;
    var
        curPrefix: string;
    begin
        curPrefix := LowerCase(copy(ss1Edid, 1, 6));
        if(curPrefix <> 'kgsim_') then begin
            Result := '';
            exit;
        end;

        Result := 'SS2_' + copy(ss1Edid, 7, length(ss1Edid));
    end;

    function findObjectByEdidSS2(edid: String): IInterface;
    var
        iFiles, iSigs, j: integer;
        curGroup: IInterface;
        curFile: IInterface;
        curRecord: IInterface;
        altEdid: string;
    begin
        Result := nil;
        if(edid = '') then exit;

        altEdid := getSS2VersionEdid(edid);
        curRecord := nil;
        for iFiles := 0 to FileCount-1 do begin
            curFile := FileByIndex(iFiles);

            if(assigned(curFile)) then begin
                if(altEdid <> '') then begin
                    curRecord := FindObjectInFileByEdid(curFile, altEdid);
                    if(assigned(curRecord)) then begin
                        Result := curRecord;
                        exit;
                    end;
                end;

                curRecord := FindObjectInFileByEdid(curFile, edid);
                if(assigned(curRecord)) then begin
                    Result := curRecord;
                    exit;
                end;
            end;
        end;
    end;


    function createReference(cell: IInterface; baseForm: IInterface; posX, posY, posZ, rotX, rotY, rotZ, scale: Float): IInterface;
    var
        cellFile: IInterface;
        dataRec: IInterface;
        curSig: string;
    begin
        curSig := Signature(baseForm);
        if(groupsToSearch.indexOf(curSig) < 0) then begin
            AddMessage('BaseForm '+EditorID(baseForm)+' cannot be placed as a reference, because it''s signature is '+curSig);
            Result := nil;
            exit;
        end;

        Result := Add(cell, 'REFR', true);
        cellFile := GetFile(cell);

        AddRequiredElementMasters(baseForm, cellFile, False);

        SetEditValue(ensurePath(Result, 'NAME'), IntToHex(GetLoadOrderFormID(baseForm), 8));
        SetEditValue(ensurePath(Result, 'XSCL'), FloatToStr(scale));

        setElementEditValues(Result, 'DATA\Position\X', posX);
        setElementEditValues(Result, 'DATA\Position\Y', posY);
        setElementEditValues(Result, 'DATA\Position\Z', posZ);

        setElementEditValues(Result, 'DATA\Rotation\X', rotX);
        setElementEditValues(Result, 'DATA\Rotation\Y', rotY);
        setElementEditValues(Result, 'DATA\Rotation\Z', rotZ);

    end;

    function fixEditorID(edid: string): string;
    var
        suffix: string;
        suffixInt: integer;
    begin
        if(edid = '') then begin
            Result := '';
            exit;
        end;

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
        levelNumStr, stageNumStr, stageEndStr, edid, rootLayerEdid, stageLayerEdid: string;
        curLayer, curLevelLayer, baseForm, refForm, targetFile: IInterface;
        flstLength, flstIndex: integer;
        scale: float;
    begin
        fields := TStringList.Create;

        fields.Delimiter := ',';
        fields.StrictDelimiter := TRUE;
        fields.DelimitedText := line;

        levelNumStr := fields[8];
        stageNumStr := fields[9];
        stageEndStr := fields[10];


        if(levelNumStr = '') then begin
            levelNumStr := '1';
        end;

        if (stageNumStr = '') then begin
            stageNumStr := '1'; //?
        end;

        if (stageEndStr = '') then begin
            stageEndStr := stageNumStr;
        end;

        // fields in v2 are like this:
        {
        0 = Form
        1 = Pos X
        2 = Pos Y
        3 = Pos Z
        4 = Rot X
        5 = Rot Y
        6 = Rot Z
        7 = Scale
        8 = iLevel
        9 = iStageNum
        10 = iStageEnd
        11 = iType
        }

        targetFile := GetFile(cell);

        rootLayerEdid := sPlanName + '_L'+levelNumStr;

        stageLayerEdid := rootLayerEdid+'_'+stageNumStr+'_'+stageEndStr;


        curLevelLayer := getLayer(targetFile, rootLayerEdid, true);
        curLayer := getLayer(targetFile, stageLayerEdid, true);

        SetElementEditValues(curLayer, 'PNAM', IntToHex(GetLoadOrderFormID(curLevelLayer), 8));

        edid := fixEditorID(fields[0]);
        if(edid = '') then begin
            fields.free;
            exit;
        end;

        baseForm := findObjectByEdidSS2(edid);
        if(not assigned(baseForm)) then begin
            AddMessage('Could not find any records for '+edid);
        end else begin

            if(Signature(baseForm) = 'FLST') then begin
                flstLength := getFormListLength(baseForm);
                if(flstLength = 0) then begin
                    baseForm := nil;
                end else begin
                    flstIndex := Random(flstLength);
                    baseForm := getFormListEntry(baseForm, flstIndex);
                end;
            end;

            if(assigned(baseForm)) then begin

                scale := 1.0;
                if(fields[7] <> '') then begin
                    scale := StrToFloat(fields[7]);
                end;

                refForm := createReference(
                    cell,
                    baseForm,
                    StrToFloat(fields[1]),
                    StrToFloat(fields[2]),
                    StrToFloat(fields[3]),
                    StrToFloat(fields[4]),
                    StrToFloat(fields[5]),
                    StrToFloat(fields[6]),
                    scale
                );
                SetEditValue(ensurePath(refForm, 'XLYR'), IntToHex(GetLoadOrderFormID(curLayer), 8));
            end else begin;
                AddMessage('FormList '+edid+' seems to be empty');
            end;

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
        groupsToSearch.add('FLST');

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

    function LoadFromCsv(): TStringList;
    var
        csvFileName: string;
        lsLines: TStringList;
    begin
        Result := nil;
        csvFileName := ShowOpenFileDialog('Select CSV', 'CSV|*.csv|All Files|*.*');
        if(csvFileName = '') then exit;

        lsLines := TStringList.Create;
        lsLines.NameValueSeparator := #44;
        lsLines.LoadFromFile(csvFileName);

        Result := lsLines;
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

        csvLines := LoadFromCsv();

        if(csvLines = nil) then begin
            Result := 1;
            AddMessage('Cancelled');
            exit;
        end;

        if(csvLines.count <= 0) then begin
            csvLines.free();
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
        
        if(planName = 'Form') then begin
            planName := 'BuildingPlan';
        end;

		fields.free;

        Randomize();

        for i:=1 to csvLines.count-1 do begin
            curLine := csvLines[i];
            processLine(selectedCell, curLine, planName);
        end;

        csvLines.free();
    end;

end.