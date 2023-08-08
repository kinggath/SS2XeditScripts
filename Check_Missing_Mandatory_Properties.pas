{
    This should generate output for when forms have missing mandatory script properties
}
unit CheckMissingMandatoryProps;
    uses PexToJson;
    uses praUtil;

    const
        progressMessageAfter = 1000;

    var
        scriptCache: TJsonObject;
        processedForms, foundErrors: cardinal;

    // Called before processing
    // You can remove it if script doesn't require initialization code
    function Initialize: integer;
    begin
        Result := 0;
        scriptCache := TJsonObject.create();
        AddMessage('Script begins.');
        processedForms := 0;
        foundErrors := 0;
    end;

    procedure addToJsonArray(newEntry: string; arr: TJsonArray);
    var
        i: integer;
    begin
        for i:=0 to arr.count-1 do begin
            if(LowerCase(arr.S[i]) = LowerCase(newEntry)) then exit;
        end;

        arr.add(newEntry);
    end;

    procedure getFilledProperties(e: IInterface; outList: TJsonObject);
    var
        curScript, scripts, propRoot, prop: IInterface;
        i, j: integer;
        scriptName, scriptNameLc, propName: string;
        scriptObj: TJsonObject;
        propArray: TJsonArray;
    begin
        scripts := ElementByPath(e, 'VMAD - Virtual Machine Adapter\Scripts');
        if(not assigned(scripts)) then exit;

        // processing code goes here
        for i := 0 to ElementCount(scripts)-1 do begin
            curScript := ElementByIndex(scripts, i);
            scriptName := geevt(curScript, 'scriptName');
            scriptNameLc := LowerCase(scriptName);

            propRoot := ElementByPath(curScript, 'Properties');

            scriptObj := outList.O[scriptNameLc];
            scriptObj.S['name'] := scriptName;

            if(assigned(propRoot)) then begin

                propArray := scriptObj.A['props'];


                for i := 0 to ElementCount(propRoot)-1 do begin
                    prop := ElementByIndex(propRoot, i);
                    propName := geevt(prop, 'propertyName');

                    addToJsonArray(propName, propArray);
                end;
            end;
        end;
    end;

    function getMandatoryProperties(scriptName: string): TJsonArray;
    var
        pexData, curObj, curProp: TJsonObject;
        propRoot, objRoot: TJsonArray;
        i, j: integer;
        userFlags: cardinal;

    begin
        if(scriptCache.Types[scriptName] = JSON_TYPE_ARRAY) then begin
            Result := scriptCache.A[scriptName];
            exit;
        end;

        Result := scriptCache.A[scriptName];


        pexData := readPexScriptName(scriptName);
        if(pexData = nil) then begin
            AddMessage('WARNING: Failed to decompile '+scriptName);
            exit;
        end;

        objRoot := pexData.A['objects'];

        for i:=0 to objRoot.count-1 do begin
            curObj := objRoot.O[i];
            if(LowerCase(curObj.S['name']) = LowerCase(scriptName)) then begin
                propRoot := curObj.A['props'];
                // iterate props
                for j:=0 to propRoot.count-1 do begin
                    curProp := propRoot.O[j];
                    userFlags := curProp.U['userFlags'];
                    if((userFlags and PEX_FLAG_MANDATORY) <> 0) then begin

                        Result.add(curProp.S['name']);
                    end;
                end;
                break;
            end;
        end;
        pexData.free();
    end;

    function getMissingList(havingList, expectedList: TJsonArray): TStringList;
    var
        missingList: TStringList;
        i, j: integer;
        curExpected: string;
        found: boolean;
    begin
        missingList := TStringList.create();

        for i:=0 to expectedList.count-1 do begin
            curExpected := expectedList.S[i];
            found := false;
            for j:=0 to havingList.count-1 do begin
                if(LowerCase(curExpected) = LowerCase(havingList.S[j])) then begin
                    found := true;
                    break;
                end;
            end;
            if(not found) then begin
                missingList.add(curExpected);
            end;
        end;

        Result := missingList;
    end;

    // called for every record selected in xEdit
    function Process(e: IInterface): integer;
    var
        curScript, scripts, baseObj: IInterface;
        i, j: integer;
        curList: TJsonObject;
        curNameLC, curName: string;
        mandatoryList, curScriptList: TJsonArray;
        missingList: TStringList;
    begin
        Result := 0;

        // comment this out if you don't want those messages
        curList := TJsonObject.create;
        // AddMessage('Checking: '+Name(e));
        getFilledProperties(e, curList);
        if(isReferenceSignature(Signature(e))) then begin
            baseObj := pathLinksTo(e, 'NAME');
            getFilledProperties(baseObj, curList);
        end;

        for i:=0 to curList.count-1 do begin
            curNameLC := curList.Names[i];
            curName := curList.O[curNameLC].S['name'];

            mandatoryList := getMandatoryProperties(curName);
            curScriptList := curList.O[curNameLC].A['properties'];

            missingList := getMissingList(curScriptList, mandatoryList);
            if(missingList.count > 0) then begin
                AddMessage('=== MISSING PROPERTIES ===');
                AddMessage('Form: '+FullPath(e));
                AddMessage('Script: '+curName);
                AddMessage('Properties: ');
                for j:=0 to missingList.count-1 do begin
                    AddMessage('    - '+missingList[j]);
                end;
                AddMessage('==========================');
                foundErrors := foundErrors + 1;
            end;
            missingList.free();
        end;

        processedForms := processedForms + 1;

        if((processedForms mod progressMessageAfter) = 0) then begin
            AddMessage('Checked '+IntToStr(processedForms)+' forms, found '+IntToStr(foundErrors)+' errors');
        end;



        curList.free();

    end;

    // Called after processing
    // You can remove it if script doesn't require finalization code
    function Finalize: integer;
    begin
        AddMessage('Script done. Processed forms: '+IntToStr(processedForms)+'. Errors: '+IntToStr(foundErrors));
        Result := 0;
        scriptCache.free();
    end;

end.