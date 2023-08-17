{
    run on quest
    SS2_C3_ConquestManager [QUST:0304BAAA]

    X count of Struct UnitSelector added to target array property on target quest
        UniqueForm = new SimSettlementsV2:ObjectReferences:UnitSelectorForm
            Copy of SS2_C3_Cacheable_UnitSelectForm0001 or SS2_C3_NonCached_UnitSelectForm0001 renamed to have number match current iteration.

        PutNPCInAlias = new Alias on target quest
            Name = CachedUnitNameHolderXXXX or NonCachedUnitNameHolderXXXX
            Check in: Optional, Allow Reuse in Quest, Stores Text, Allow Disabled, Allow Reserved

        PutSelectorInAlias = new Alias on target quest
            Name = CachedUnitSelectorNameApplyXXXX or NonCachedUnitSelectorNameApplyXXXX
            Check in: Optional, Uses Stored Text
            Display Name = new Message form
                Copy of SS2_TokenName_CacheableUnitSelect_0001 or SS2_TokenName_NonCachedUnitSelect_0001 updated title to have XXXX match the number in the EDID


        gRankInstanceGlobal = new global EDID = SS2_Instance_CacheableUnitSelectorRankXXXX or SS2_Instance_NonCachedUnitSelectorRankXXXX

        gSpecialInstanceGlobal = new global EDID = SS2_Instance_CacheableUnitSelectorSpecialRatingXXXX or SS2_Instance_NonCachedUnitSelectorSpecialRatingXXXX

}
unit GenerateQuestAliases;
    uses 'SS2\praUtil';

    const
        // hardcoded for now
        questScriptName='SimSettlementsV2:quests:ConquestManager';
        //questPropName='CacheableUnitSelectorMaps'; 
	questPropName='NonCachedUnitSelectorMaps';
        nrOfEntries=1; // How many to create?

        isCached=false;

    var
        ss2file: IInterface;
        targetFile: IInterface;

        // templates
        SS2_C3_Cacheable_UnitSelectForm0001: IInterface;
        SS2_C3_NonCached_UnitSelectForm0001: IInterface;
        SS2_TokenName_CacheableUnitSelect_0001: IInterface;
        SS2_TokenName_NonCachedUnitSelect_0001: IInterface;
        globalTemplate: IInterface;
        // stuff

        displayNameIndex: integer;
        unitSelectIndex: integer;
        putInAliasIndex: integer;
        rankInstanceGlobalIndex: integer;
        specialInstanceGlobalIndex: integer;

        nextQuestAliasId: integer;


    {
        Pads a number to given length by prefixing 0
    }
    function padNr(nr, targetLength: integer): string;
    begin
        Result := IntToStr(nr);

        while(length(Result) < targetLength) do begin
            Result := '0' + Result;
        end;
    end;

        {
        Set a script property. Cannot set the value to structs or arrays.
    }
    procedure setScriptPropAlias(script, quest, alias: IInterface);
    var
        propElem: IInterface;
    begin
        propElem := createRawScriptProp(script, propName);
        setPropertyValueAlias(propElem, quest, alias);
    end;

    function getAliasId(alias: IInterface): integer;
    var
        maybeId: string;
    begin
        maybeId := GetElementEditValues(alias, 'ALST'); // reference alias
        if(maybeId = '') then begin
            maybeId := GetElementEditValues(alias, 'ALCS'); // collection alias
            if(maybeId = '') then begin
                maybeId := GetElementEditValues(alias, 'ALLS'); // location alias
                if(maybeId = '') then begin
                    // fail
                    AddMessage('Failed to get alias for this:');
                    dumpElem(alias);
                    Result := -1;
                    exit;
                end;
            end;
        end;
        Result := StrToInt(maybeId);
    end;

    {
        Set a struct member. Cannot set the value to arrays.
    }
    procedure setStructMemberAlias(struct: IInterface; memberName: string; quest, alias: IInterface);
    var
        propElem: IInterface;
    begin
        propElem := createRawStructMember(struct, memberName);
        setPropertyValueAlias(propElem, quest, alias);
    end;

    procedure setPropertyValueAlias(propElem, quest, alias: IInterface);
    var
        aliasIndex: integer;
        aliasName, aliasStr: string;
    begin
        aliasIndex := getAliasId(alias);
        aliasStr := IntToStr(aliasIndex);
        SetElementEditValues(propElem, 'Type', 'Object');
        SetLinksTo(ElementByPath(propElem, 'Value\Object Union\Object v2\FormID'), quest);
        SetElementEditValues(propElem, 'Value\Object Union\Object v2\Alias', aliasStr);

    end;

    function getRankInstanceGlobal(): IInterface;
    var
        edid, edidPrefix, groupName: string;
        template, existing, group: IInterface;
    begin
        if(isCached) then begin// or
            edidPrefix := 'SS2_Instance_CacheableUnitSelectorRank';
        end else begin
            edidPrefix := 'SS2_Instance_NonCachedUnitSelectorRank';
        end;

        repeat
            edid := edidPrefix+padNr(rankInstanceGlobalIndex, 4);
            existing := FindObjectByEdid(edid);
            rankInstanceGlobalIndex := rankInstanceGlobalIndex + 1;
        until (not assigned(existing));

        addRequiredMastersSilent(globalTemplate, targetFile);
        Result := wbCopyElementToFile(globalTemplate, targetFile, true, true);
        SetElementEditValues(Result, 'EDID', edid);
        SetElementEditValues(Result, 'Record Header\Record Flags', '');
        SetElementEditValues(Result, 'FLTV', '0');
    end;

    function getSpecialInstanceGlobal(): IInterface;
    var
        edid, edidPrefix, groupName: string;
        template, existing, group: IInterface;
    begin//S2_Instance_CacheableUnitSelectorSpecialRatingXXXX or SS2_Instance_NonCachedUnitSelectorSpecialRatingXXXX
        if(isCached) then begin// or
            edidPrefix := 'SS2_Instance_CacheableUnitSelectorSpecialRating';
        end else begin
            edidPrefix := 'SS2_Instance_NonCachedUnitSelectorSpecialRating';
        end;

        repeat
            edid := edidPrefix+padNr(specialInstanceGlobalIndex, 4);
            existing := FindObjectByEdid(edid);
            specialInstanceGlobalIndex := specialInstanceGlobalIndex + 1;
        until (not assigned(existing));
//
        addRequiredMastersSilent(globalTemplate, targetFile);
        Result := wbCopyElementToFile(globalTemplate, targetFile, true, true);
        SetElementEditValues(Result, 'EDID', edid);
        SetElementEditValues(Result, 'Record Header\Record Flags', '');
        SetElementEditValues(Result, 'FLTV', '0');
    end;

    procedure updateDisplayName(displayName, npcAlias, rankInstanceGlobal, specialInstanceGlobal: IInterface);
    var
        currentName, rank, specialRating, resultStr: string;
    begin
        currentName := GetElementEditValues(npcAlias, 'ALID');
        rank := EditorID(rankInstanceGlobal);
        specialRating := EditorID(specialInstanceGlobal);
        resultStr := '<Alias.CurrentName='+currentName+'> - <Token.Name=UnitTypeOrLoadout> Rank <Global='+rank+'> [SR: <Global='+specialRating+'>]';

        SetElementEditValues(displayName, 'FULL', resultStr);
    end;

    function getDisplayNameForm(): IInterface;
    var
        edid, edidPrefix, groupName: string;
        template, existing, group: IInterface;
    begin
        if(isCached) then begin
            edidPrefix := 'SS2_TokenName_CacheableUnitSelect_';
            template := SS2_TokenName_CacheableUnitSelect_0001;
        end else begin
            edidPrefix := 'SS2_TokenName_NonCachedUnitSelect_';
            template := SS2_TokenName_NonCachedUnitSelect_0001;
        end;

        repeat
            edid := edidPrefix+padNr(displayNameIndex, 4);
            existing := FindObjectByEdid(edid);
            displayNameIndex := displayNameIndex + 1;
        until (not assigned(existing));

        addRequiredMastersSilent(template, targetFile);
        Result := wbCopyElementToFile(template, targetFile, true, true);
        SetElementEditValues(Result, 'EDID', edid);
    end;


    function getUnitSelectForm(): IInterface;
    var
        edid, edidPrefix, groupName: string;
        template, existing, group: IInterface;
    begin
        if(isCached) then begin
            edidPrefix := 'SS2_C3_Cacheable_UnitSelectForm';
            template := SS2_C3_Cacheable_UnitSelectForm0001;
        end else begin
            edidPrefix := 'SS2_C3_NonCached_UnitSelectForm';
            template := SS2_C3_NonCached_UnitSelectForm0001;
        end;


        //groupName := Signature(template);
        //group := GroupBySignature(targetFile, groupName);

        repeat
            edid := edidPrefix+padNr(unitSelectIndex, 4);
            existing := FindObjectByEdid(edid);
            unitSelectIndex := unitSelectIndex + 1;
        until (not assigned(existing));

        AddMessage('unused edid: '+edid);
        addRequiredMastersSilent(template, targetFile);
        Result := wbCopyElementToFile(template, targetFile, true, true);
        SetElementEditValues(Result, 'EDID', edid);

    end;

    function createAlias(targetQuest: IInterface): IInterface;
    var
        aliases, curAlias: IInterface;
        prevCount, i, curId, prevMaxValue: integer;
        curIdStr: string;
    begin
        //  (e.g. ALST = Reference Alias vs. ALCS = Collection Alias vs. ALLS = Location Alias
        // ALST seems to be the index for ref aliases. ALCS is for Collection Aliases
        aliases := ElementByPath(targetQuest, 'Aliases');
        if(not assigned(aliases)) then begin
            aliases := Add(targetQuest, 'Aliases', true);
            if(ElementCount(aliases) > 0)  then begin
                curAlias := ElementByIndex(aliases, 0);
                Result := 0;

                //curAlias := ElementAssign(aliases, HighInteger, nil, False);
                //SetElementEditValues(curAlias, 'ALID', charName);
                SetElementEditValues(curAlias, 'ALST', '0');
                SetElementEditValues(targetQuest, 'ANAM', '1');
                nextQuestAliasId := 1;
                Result := curAlias;
                exit;
            end;
        end;

        if(nextQuestAliasId = 0) then begin
            // find it
            for i:=0 to ElementCount(aliases)-1 do begin
                curAlias := ElementByIndex(aliases, i);
                //curName := LowerCase(trim(GetElementEditValues(curAlias, 'ALID')));
                curId := getAliasId(curAlias);


                if(curId > nextQuestAliasId) then begin
                    nextQuestAliasId := curId;
                end;

            end;
        end;

        curAlias := ElementAssign(aliases, HighInteger, nil, False);
        nextQuestAliasId := nextQuestAliasId + 1;
        SetElementEditValues(curAlias, 'ALST', IntToStr(nextQuestAliasId));


        prevMaxValue := StrToInt(GetElementEditValues(targetQuest, 'ANAM'));
        prevMaxValue := prevMaxValue+1;
        SetElementEditValues(targetQuest, 'ANAM', IntToStr(prevMaxValue));
        Result := curAlias;
    end;


    function getUnitNameHolderName(nr: integer): string;
    begin
        if(isCached) then begin
            Result := 'CachedUnitNameHolder'+padNr(nr, 4);
        end else begin
            Result := 'NonCachedUnitNameHolder'+padNr(nr, 4);
        end;
    end;

    function getUnitSelectorApplyName(nr: integer): string;
    begin
        if(isCached) then begin
            Result := 'CachedUnitSelectorNameApply'+padNr(nr, 4);
        end else begin
            Result := 'NonCachedUnitSelectorNameApply'+padNr(nr, 4);
        end;
    end;

    function findHighestIndex(prop: IInterface): integer;
    var
        i, len, curVal: integer;
        val, curEntry, member: IInterface;
        aliasStr, nrStr: string;
    begin
        Result := 0;
        //dumpElem(prop);
        val := ElementByPath(prop, 'Value\Array of Struct');
        for i:=0 to ElementCount(val)-1 do begin
            curEntry := ElementByIndex(val, i);
            member := getRawStructMember(curEntry, 'PutNPCInAlias');
            {Value\Object Union\Object v2=
              FormID}
            aliasStr := GetElementEditValues(member, 'Value\Object Union\Object v2\Alias');
            if(aliasStr <> '') then begin
                len := length(aliasStr);
                nrStr := copy(aliasStr, len-3, len);
                curVal := StrToInt(nrStr);
                if(curVal > Result) then begin
                    Result := curVal;
                end;
            end;
            //dumpElem(curEntry);
        end;
    end;
    
    procedure registerGlobal(quest, global: IInterface);
    var
        globalList, newEntry: IInterface;
    begin
        globalList := ElementByPath(quest, 'Text Display Globals');
        newEntry := ElementAssign(globalList, HighInteger, nil, False);
        //newEntry := //ElementAssign(globalList, HighInteger, nil, False);
        //setPathLinksTo(newEntry, 'QTGL', global);
        setLinksTo(newEntry, global);
    end;

    procedure processQuest(quest: IInterface);
    var
        script, propRoot, curStruct, uniqForm, npcAlias, selectorAlias, displayName, rankInstanceGlobal, specialInstanceGlobal: IInterface;
        i, unhId, aliasIndex, highestIndex: integer;
        unhName, usaName: string;
    begin
        script := getScript(quest, questScriptName);
        if(not assigned(script)) then begin
            AddMessage('Didn''t find  '+questScriptName);
            exit;
        end;
        targetFile := GetFile(quest);


        propRoot := getOrCreateScriptProp(script, questPropName, 'Array of Struct');

        highestIndex := findHighestIndex(propRoot);
        AddMessage('Highest: '+IntToStr(highestIndex));

        for i:=1 to nrOfEntries do begin
            AddMessage('Would be adding prop #'+IntToStr(i));
            curStruct := appendStructToProperty(propRoot);

            // create unique form
            uniqForm := getUnitSelectForm();

            setStructMember(curStruct, 'UniqueForm', uniqForm);

            // create PutNPCInAlias
            // create alias itself
            npcAlias := createAlias(quest);

            unhId := StrToInt(GetElementEditValues(npcAlias, 'ALST'));
            unhName := getUnitNameHolderName(i+highestIndex);
            SetElementEditValues(npcAlias, 'ALID', unhName);
            SetElementEditValues(npcAlias, 'FNAM', '0101000111');//Optional=1, Allow Reuse in Quest=1, Allow Disabled=1, Stores Text=1, Allow Reserved=1

            // now try to put it into the propery
            // aliasIndex := StrToInt(GetElementEditValues(npcAlias, 'ALST'));

            setStructMemberAlias(curStruct, 'PutNPCInAlias', quest, npcAlias);


            // selector alias
            selectorAlias := createAlias(quest);
            usaName := getUnitSelectorApplyName(i+highestIndex);
            SetElementEditValues(selectorAlias, 'ALID', usaName);
            SetElementEditValues(selectorAlias, 'FNAM', '010000000000001');//Optional=1, Uses Stored Text=1
            // put in property
            setStructMemberAlias(curStruct, 'PutSelectorInAlias', quest, selectorAlias);

            displayName := getDisplayNameForm();
            setPathLinksTo(selectorAlias, 'ALDN', displayName);

            // now the globals
            rankInstanceGlobal := getRankInstanceGlobal();
            setStructMember(curStruct, 'gRankInstanceGlobal', rankInstanceGlobal);
            registerGlobal(quest, rankInstanceGlobal);

            specialInstanceGlobal := getSpecialInstanceGlobal();
            setStructMember(curStruct, 'gSpecialInstanceGlobal', specialInstanceGlobal);
            registerGlobal(quest, specialInstanceGlobal);

            // finally, update the MESG
            updateDisplayName(displayName, npcAlias, rankInstanceGlobal, specialInstanceGlobal);
        end;
    end;


    // Called before processing
    // You can remove it if script doesn't require initialization code
    function Initialize: integer;
    begin
        Result := 1;
        ss2file := FindFile('SS2.esm');
        if(not assigned(ss2file)) then begin
            AddMessage('Failed to find SS2.esm');
            exit;
        end

        SS2_C3_Cacheable_UnitSelectForm0001 := FindObjectByEdid('SS2_C3_Cacheable_UnitSelectForm0001');
        SS2_C3_NonCached_UnitSelectForm0001 := FindObjectByEdid('SS2_C3_NonCached_UnitSelectForm0001');
        SS2_TokenName_CacheableUnitSelect_0001 := FindObjectByEdid('SS2_TokenName_CacheableUnitSelect_0001');
        SS2_TokenName_NonCachedUnitSelect_0001 := FindObjectByEdid('SS2_TokenName_NonCachedUnitSelect_0001');
        globalTemplate := FindObjectByEdid('SS2_ModVersion');

        if(not assigned(SS2_C3_Cacheable_UnitSelectForm0001)) or (not assigned(SS2_C3_NonCached_UnitSelectForm0001)) or (not assigned(SS2_TokenName_CacheableUnitSelect_0001)) or (not assigned(SS2_TokenName_NonCachedUnitSelect_0001)) then begin
            AddMessage('Failed to find form');
            exit;
        end;


        Result := 0;
        nextQuestAliasId := 0;

        unitSelectIndex := 2;
        displayNameIndex := 2;

        rankInstanceGlobalIndex:=1;
        specialInstanceGlobalIndex:=1;
    end;


    // called for every record selected in xEdit
    function Process(e: IInterface): integer;
    begin
        Result := 0;

        // comment this out if you don't want those messages
        if(Signature(e) = 'QUST') then begin
            processQuest(e);
        end;

        // processing code goes here

    end;

    // Called after processing
    // You can remove it if script doesn't require finalization code
    function Finalize: integer;
    begin
        Result := 0;
    end;

end.

