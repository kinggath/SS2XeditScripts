{
    This will scan the target file for redundant spawn MISCs, and recycle then.
    Run on anything within the target file.
}
unit RecycleRedundantMiscs;
    uses 'SS2\SS2Lib';

    var
        miscCache: TStringList;
        targetFile: IInterface;
		changesDone: boolean;

    procedure replaceRecordUsage(haystack, searchFor, replaceBy: IInterface);
    var
        i: integer;
        curChild, curLinksTo: IInterface;
    begin
        curLinksTo := LinksTo(haystack);
        if(assigned(curLinksTo)) then begin
            if(Equals(curLinksTo, searchFor)) then begin
                AddMessage('Replacing usage');
                setLinksTo(haystack, replaceBy);
            end;
            exit;
        end;
        for i:=0 to ElementCount(haystack)-1 do begin
            curChild := ElementByIndex(haystack, i);
            // curLinksTo := LinksTo(haystack);
            replaceRecordUsage(curChild, searchFor, replaceBy);
        end;
    end;

    // Called before processing
    // You can remove it if script doesn't require initialization code
    function Initialize: integer;
    begin
        Result := 0;
        initSS2Lib();
        miscCache := TStringList.create;
        miscCache.sorted := true;
        targetFile := nil;
		changesDone := false;
    end;

    procedure processMisc(e: IInterface);
    var
        script, oldMisc, curRef: IInterface;
        key, iTypeType: string;
        i, oldIndex, fixedIType: integer;
    begin

        // maybe this is a recycled misc?
        if(strStartsWith(EditorID(e), recycleableMiscPrefix)) then begin
            exit;
        end;

        script := getScript(e, 'SimSettlementsV2:MiscObjects:StageItem');
        if(not assigned(script)) then exit;
        
        // hack against a stupid mistake I made...
        iTypeType := getScriptPropType(script, 'iType');
        if(iTypeType = 'Float') then begin
            fixedIType := Trunc(getScriptProp(script, 'iType'));
            setScriptProp(script, 'iType', fixedIType);
        end;

        key := getMiscLookupKeyFromScript(script);
        if(key = '') then exit;
        // AddMessage('Processing: ' + EditorID(e)+', '+key);

        oldIndex := miscCache.indexOf(key);
        if(oldIndex < 0) then begin
            miscCache.AddObject(key, e);
            exit;
        end;
		
		changesDone := true;

        // otherwise replace... oof
        oldMisc := ObjectToElement(miscCache.Objects[oldIndex]);
        AddMessage('Found redundancy: '+EditorID(e)+' is redundant with '+EditorID(oldMisc));

        for i:=0 to ReferencedByCount(e)-1 do begin
            curRef := ReferencedByIndex(e, i);
            replaceRecordUsage(curRef, e, oldMisc);
        end;

        AddMessage('Recycling '+EditorID(e));
        recycleSpawnMiscIfPossible(e, nil, targetFile);

    end;

    // called for every record selected in xEdit
    function Process(e: IInterface): integer;
    var
        script, oldMisc, curRef: IInterface;
        key: string;
        i, oldIndex: integer;
    begin
        Result := 0;

        if(not assigned(targetFile)) then begin
            targetFile := GetFile(e);
        end;

    end;
	
	procedure forceRegenerateCache(targetFile: IInterface);
	begin
		loadMiscsFromCache(nil);
		loadRecycledMiscsNoCacheFile(targetFile, true);
	end;

    // Called after processing
    // You can remove it if script doesn't require finalization code
    function Finalize: integer;
    var
        curElem, miscGroup: IInterface;
        i: integer;
    begin
        if(not assigned(targetFile)) then exit;
        miscGroup := GroupBySignature(targetFile, 'MISC');

        if(not assigned(miscGroup)) then exit;

        loadRecycledMiscsNoCacheFile(targetFile, false);
		// AddMessage('Finished building Spawn Misc cache. Found '+IntToStr(miscItemCache.count)+' recycled Miscs');

        for i:=0 to ElementCount(miscGroup)-1 do begin
            curElem := ElementByIndex(miscGroup, i);
            processMisc(curElem);
        end;
		
		if(changesDone) then begin
			// now force-regenerate the cache file
			forceRegenerateCache(targetFile);
		end;

        Result := 0;
        cleanupSS2Lib();
        miscCache.free();
    end;

end.