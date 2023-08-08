{
  Takes a csv with 2 or 3 columns and updates a quest's dialogue accordingly. The first column should be the sound file name for the voice line without the extension, the second column should be the text of that dialogue line. 
  
  The third column is optional and can be the face descriptor portion of any of the AnimFaceArchetype keyword EDIDs (do not include the AnimFaceArchetype part) - ex. for AnimFaceArchetypeAfraid, just type Afraid in the cell to set the facial animation for that line to AnimFaceArchetypeAfraid.
}
unit DialogUpdater;
    uses praUtil, dubhFunctions;
    
    var
        targetFile: IInterface;
        
    function findResponseByNumber(e: IInterface; nr: integer): IInterface;
    var
        responses, curRsp, rspData, curNr, i: IInterface;
    begin
        Result := nil;
        //dumpElem(e);
        responses := ElementByName(e, 'Responses');
        
        for i:=0 to ElementCount(responses) do begin
            curRsp := ElementByIndex(responses, i);
          //  dumpElem(curRsp);
            rspData := ElementBySignature(curRsp, 'TRDA');
            curNr := StrToInt(GetElementEditValues(rspData, 'Response number'));
            if(curNr = nr) then begin
                Result := curRsp;
                exit;
            end;
        end;
    end;
    
    function fixFormId(forFile: IInterface; formID: cardinal): cardinal;
    begin
        Result := formID or 16777216*getLoadOrder(forFile); // 0x01000000
    end;
    
    function getEmotionKeyword(emotion: string): IInterface;
    var
        edid: string;
    begin
        Result := nil;
        
        if(emotion = '') then exit;
        
		
		// First check if user used full keyword
		//Result := FindObjectByEdid(emotion);
		
		//if(not assigned(Result)) then begin
			// See if they just used the emotion name
			edid := 'AnimFaceArchetype'+strUpperCaseFirst(emotion);
        
			AddMessage('Emotion KW is '+edid);
			Result := FindObjectByEdid(edid);
        //end;
    end;
        
    procedure processLine(line: string);
    var
        fields, formIdThing: TStringList;
        formIdPart, text, lipGenText, formIdStr, indexStr, emotionString: string;
        targetForm, rsp, emotionKw, trda: IInterface;
        responseNr: integer;
        
        formID: cardinal;
    begin
        fields := TStringList.Create;

        fields.Delimiter := ',';
        fields.StrictDelimiter := TRUE;
        fields.DelimitedText := line;
        
        if(fields.count < 2) then begin
            AddMessage('Invalid line: '+line);
            exit;
        end;
        
		// Assuming we're using the exported sheets simplified to 4 columns by https://www.simsettlements.com/tools/dialogueconverter.php
		// Columns are: Filename, Alias, Line Text, Notes
		// Two extra optional columns can be added: Face animation keyword, and alternate lip sync generation text
        formIdPart    := fields[0];
        text          := fields[2];
        emotionString := '';
		lipGenText := '';
        if(fields.count >= 4) then begin
            emotionString := fields[3];
        end;
		
		if(fields.count >= 5) then begin
            lipGenText := fields[4];
        end;
        
        formIdThing := TStringList.create;
        formIdThing.Delimiter := '_';
        formIdThing.StrictDelimiter := TRUE;
        formIdThing.DelimitedText := formIdPart;
        addMessage('formIdPart = '+formIdPart);
        
        if(formIdPart = '') then begin
            exit;
        end;
        
        formIdStr := formIdThing[0];
        indexStr := formIdThing[1];
        
        formIdThing.free;
        fields.free;
        
        responseNr := StrToInt(indexStr);
        formID := fixFormId(targetFile, StrToInt('0x'+formIdStr));
        // RecordByFormID needs a loadorder-corrected formID. the docs are lying.
        targetForm := RecordByFormID(targetFile, formID, true);
        if(not assigned(targetForm)) then begin
            AddMessage('Could not find any form with FormID '+formIdStr+' in the current file');
            exit;
        end;
        
        
        rsp := findResponseByNumber(targetForm, responseNr);
        if(not assigned(rsp)) then begin
            AddMessage('Could not find response #'+indexStr+' in '+formIdStr);
            exit;
        end;
        
        SetElementEditValues(rsp, 'NAM1 - Response Text', text);
        
        if(emotionString <> '') then begin
            emotionKw := getEmotionKeyword(emotionString);
            if(assigned(emotionKw)) then begin
                trda := EnsurePath(rsp, 'TRDA');
				setPathLinksTo(trda, 'Emotion', emotionKw);
            end;
        end;
		
		if(lipGenText <> '') then begin
			SetElementEditValues(rsp, 'NAM4 - Alternate LIP Text', lipGenText);
		end;
        
    end;

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

        if(not assigned(targetFile)) then begin
            targetFile := GetFile(e);
        end;

    end;

    // Called after processing
    // You can remove it if script doesn't require finalization code
    function Finalize: integer;
    var
        i: integer;
        curLine: string;
        csvLines: TStringList;
    begin
        Result := 0;
        
        if(not assigned(targetFile)) then begin
            AddMessage('Error: No file selected');
            exit;
        end;
        
        AddMessage('Target File: '+GetFileName(targetFile));
        
        csvLines := LoadFromCsv(false, false, false, '');

        if(csvLines.count <= 0) then begin
            Result := 1;
            AddMessage('No CSV file loaded!');
            exit;
        end;
        
        for i:=1 to csvLines.count-1 do begin
            curLine := csvLines[i];
            processLine(curLine);
        end;
        
        csvLines.free();        
    end;

end.
