{
    New script template, only shows processed records
    Assigning any nonzero value to Result will terminate script
}
unit userscript;

    uses 'SS2\SS2Lib';

    var
        // templates
        // =========
        // for bases
        SS2_ap_FactionFlag_BaseColor_Template: IInterface;
        SS2_Tag_FactionFlag_Base_Template: IInterface;
        SS2_MS_FactionFlagBase_Template: IInterface;
        SS2_miscmod_FactionFlag_Base_Template: IInterface;
        SS2_FactionFlag_Base_Template: IInterface;
        SS2_co_FactionFlag_Base_Template: IInterface;
		SS2_miscmod_FactionFlag_BaseColor_Template: IInterface;
        SS2_FactionFlag_BaseColor_Template: IInterface;
        SS2_co_FactionFlag_BaseColor_Template: IInterface;
        SS2_Tag_FactionFlag_BaseColor_Template: IInterface;
        SS2_Tag_FactionFlag_HasBaseColorSelected: IInterface;

        // for emblems
        SS2_ap_FactionFlag_EmblemColor_Template: IInterface;
        SS2_Tag_FactionFlag_Emblem_Template: IInterface;
        SS2_MS_FactionFlagEmblem_Template: IInterface;
        SS2_miscmod_FactionFlag_Emblem_Template: IInterface;
        SS2_FactionFlag_Emblem_Template: IInterface;
        SS2_co_FactionFlag_Emblem_Template: IInterface;
        SS2_miscmod_FactionFlag_EmblemColor_Template: IInterface;
        SS2_FactionFlag_EmblemColor_Template: IInterface;
        SS2_Tag_FactionFlag_HasEmblemColorSelected: IInterface;

        // for in-world objects
        SS2_FactionFlag_FlagDown_Template: IInterface;
        SS2_FactionFlag_FlagWaving_Template: IInterface;
        SS2_FactionFlag_HalfCircleFlag01_Template: IInterface;
        SS2_FactionFlag_HalfCircleFlag02_Template: IInterface;
        SS2_FactionFlag_StaticBanner_Template: IInterface;
        SS2_FactionFlag_StaticBannerTorn_Template: IInterface;
        SS2_FactionFlag_WallFlag_Template: IInterface;
        SS2_FactionFlag_WavingBanner_Template: IInterface;
        SS2_ThemeDefinition_EmpireFlags_Template: IInterface;

        // for colors
        SS2_Tag_FactionFlag_EmblemColor_Template: IInterface;

        // lookup
        existingContent: TJsonObject;
        edidLookupCache: TStringList;

        // input data
        filePathColors: string;
        filePathEmblems: string;
        filePathBases: string;

        doRegenerateColors: boolean;
        doRegenerateEmblems: boolean;
        doRegenerateBases: boolean;
        doRegenerateArmors: boolean;

        importDataColors : TJsonObject;
        importDataEmblems: TJsonObject;
        importDataBases: TJsonObject;


        // other
        targetFile: IInterface;
        
    function GetFormByEdidCached(edid: string): IInterface;
    var
        cacheIndex: integer;
    begin
        // AddMessage('> checking '+edid);
        cacheIndex := edidLookupCache.indexOf(edid);
        if(cacheIndex >= 0) then begin
            // AddMessage('> cache hit! '+ IntToStr(cacheIndex));
            Result := ObjectToElement(edidLookupCache.Objects[cacheIndex]);
            exit;
        end;
        
        //AddMessage('> cache miss');
        Result := GetFormByEdid(edid);
        edidLookupCache.addObject(edid, Result);
    end;

    function omodHasKeyword(omod, kw: IInterface): boolean;
    var
        data, properties, curProp, curKw: IInterface;
        i, cnt: integer;
    begin
        
        omod := getExistingElementOverrideOrClosest(omod, targetFile);

        Result := false;
        data := ElementByPath(omod, 'DATA');
        properties := ElementByPath(data, 'Properties');
        cnt := ElementCount(properties);
        for i:=0 to cnt-1 do begin
            curProp := ElementByIndex(properties, i);
            if(GetElementEditValues(curProp, 'Property') = 'Keywords') then begin
                curKw := pathLinksTo(curProp, 'Value 1 - FormID');
                if(isSameForm(curKw, kw)) then begin
                    Result := true;
                    exit;
                end;
            end;
        end;
    end;

    function getOmodMatswap(omod: IInterface): IInterface;
    var
        data, properties, curProp: IInterface;
        i, cnt: integer;
    begin
        omod := getExistingElementOverrideOrClosest(omod, targetFile);

        Result := nil;
        data := ElementByPath(omod, 'DATA');
        properties := ElementByPath(data, 'Properties');
        cnt := ElementCount(properties);
        for i:=0 to cnt-1 do begin
            curProp := ElementByIndex(properties, i);

            if(GetElementEditValues(curProp, 'Property') = 'MaterialSwaps') then begin
                Result := pathLinksTo(curProp, 'Value 1 - FormID');
                exit;
            end;
        end;
    end;

    function getReplacementMat(mswp: IInterface): string;
    var
        subs, curSub: IInterface;
        cnt, i: integer;
        curStr: string;
    begin
        mswp := getExistingElementOverrideOrClosest(mswp, targetFile);
        
        Result := '';
        subs := ElementByPath(mswp, 'Material Substitutions');
        cnt := ElementCount(subs);
        if(cnt = 1) then begin
            curSub := ElementByIndex(subs, 0);
            Result := GetElementEditValues(curSub, 'SNAM');
            exit;
        end;

        for i:=0 to cnt-1 do begin
            curSub := ElementByIndex(subs, i);
            curStr := GetElementEditValues(curSub, 'SNAM');
            if(not strEndsWithCI(curStr, '_2Sided.BGSM')) then begin
                Result := curStr;
                exit;
            end;
        end;
    end;

    function registerBase(e: IInterface; nameForEdid, baseName, descr, matPath, modelPath: string; hasColors: boolean): TJsonObject;
    var
        baseObj: TJsonObject;
    begin
        baseObj := existingContent.O['bases'].O[nameForEdid];
        baseObj.S['edidStr'] := nameForEdid;
        baseObj.S['name'] := baseName;
        baseObj.S['form'] := FormToAbsStr(MasterOrSelf(e));
        baseObj.S['description'] := descr;
        baseObj.S['materialPath'] := matPath;
        baseObj.S['modelPath'] := modelPath;
        baseObj.B['hasColors'] := hasColors;

        Result := baseObj;
    end;

    procedure registerEmblem(e: IInterface; nameForEdid, baseName, matPath: string; hasColors: boolean);
    var
        baseObj: TJsonObject;
    begin
        baseObj := existingContent.O['emblems'].O[nameForEdid];

        baseObj.S['edidStr'] := nameForEdid;
        baseObj.S['form'] := FormToAbsStr(MasterOrSelf(e));
        baseObj.S['name'] := baseName;
        baseObj.S['materialPath'] := matPath;
        baseObj.B['hasColors'] := hasColors;
    end;

    procedure registerColor(kwBase, kwEmblem: IInterface; colorName, colorNameForEdid, indexStr: string);
    var
        colorObj: TJsonObject;
    begin

        colorObj := existingContent.O['colors'].O[colorNameForEdid];

        colorObj.S['edidStr'] := colorNameForEdid;
        colorObj.S['baseKeyword'] := FormToAbsStr(MasterOrSelf(kwBase));
        colorObj.S['emblemKeyword'] := FormToAbsStr(MasterOrSelf(kwEmblem));
        colorObj.S['indexStr'] := indexStr;
        colorObj.S['name'] := colorName;
    end;

    function getOmodUniqueKeyword(e: IInterface): IInterface;
    var
        omodProps, omodFirstProp: IInterface;
    begin
        e := getExistingElementOverrideOrClosest(e, targetFile);
        Result := nil;
        omodProps := ElementByPath(e, 'DATA\Properties');
        if(assigned(omodProps)) then begin
            if(ElementCount(omodProps) > 0) then begin
                omodFirstProp := ElementByIndex(omodProps, 0);
                Result := PathLinksTo(omodFirstProp, 'Value 1 - FormID');

            end;
        end;
    end;

    procedure registerExistingBase(e: IInterface);
    var
        baseMatPath, baseModelsPath, baseName, descr, nameForEdid, modelPath, curEdid: string;
        hasColors: boolean;
        omodSwap: IInterface;
        baseObj: TJsonObject;
        omodProps, omodFirstProp, uniqueKw: IInterface;
    begin
        e := getExistingElementOverrideOrClosest(e, targetFile);
        curEdid := EditorID(e);
        
        if(Pos('template', LowerCase(curEdid)) > 0) then begin
            exit;
        end;
        
        
        omodSwap := getOmodMatswap(e);
        if(not assigned(omodSwap)) then begin
            AddMessage('Base without matswap: ' + FullPath(e));
            exit;
        end;

        //AddMessage('Found omod ' + FullPath(omodSwap));
        baseMatPath := getReplacementMat(omodSwap);
        //AddMessage('baseMatPath = ' + baseMatPath);

        baseName := GetElementEditValues(e, 'FULL');
        baseName := regexReplace(baseName, '^Base Material - ', '');
        //AddMessage('baseName = ' + baseName);

        descr := GetElementEditValues(e, 'DESC');
        //AddMessage('descr = ' + descr);

        hasColors := (not omodHasKeyword(e, SS2_Tag_FactionFlag_HasBaseColorSelected));
        //AddMessage('hasColors = ' + BoolToStr(hasColors));

        AddMessage('Found flag base: ' + baseName);
        nameForEdid := cleanStringForEditorID(baseName);

        modelPath := '';
        // get the KW, try reading the matpath from
        // setElementEditValues(uniqueKeyword, 'DNAM', baseModelsPath);
        // should be the first property
        uniqueKw := getOmodUniqueKeyword(e);
        if(assigned(uniqueKw)) then begin
            modelPath := getElementEditValues(uniqueKw, 'DNAM');
        end;

        registerBase(e, nameForEdid, baseName, descr, baseMatPath, modelPath, hasColors);
    end;

    procedure registerExistingEmblem(e: IInterface);
    var
        omodSwap: IInterface;
        baseName, baseMatPath, nameForEdid, curEdid: string;
        hasColors: boolean;
        baseObj: TJsonObject;
    begin
        e := getExistingElementOverrideOrClosest(e, targetFile);
        curEdid := EditorID(e);
        
        if(Pos('template', LowerCase(curEdid)) > 0) then begin
            exit;
        end;
        omodSwap := getOmodMatswap(e);
        if(not assigned(omodSwap)) then begin
            AddMessage('Emblem without matswap: ' + FullPath(e));
            exit;
        end;
        // figure out:
        // - Column A: Emblem material path: from the MaterialSwaps, the one without _2sided.bgsm
        // - Column B: Emblem name: FULL without prefix "Emblem - "
        // - Column C: Supports Color Indexing? Y/N: has SS2_Tag_FactionFlag_HasEmblemColorSelected
        baseMatPath := getReplacementMat(omodSwap);
        baseName := GetElementEditValues(e, 'FULL');
        baseName := regexReplace(baseName, '^Emblem - ', '');

        hasColors := (not omodHasKeyword(e, SS2_Tag_FactionFlag_HasEmblemColorSelected));

        AddMessage('Found flag emblem: ' + baseName);
        nameForEdid := cleanStringForEditorID(baseName);

        registerEmblem(e, nameForEdid, baseName, baseMatPath, hasColors);
    end;

    procedure registerExistingColor(e: IInterface);
    var
        colorName, indexString, colorNameForEdid, curEdid: string;
        colorObj: TJsonObject;
        isEmblemKeyword, addNew: boolean;
        indexStr: string;
    begin
        e := getExistingElementOverrideOrClosest(e, targetFile);
        curEdid := EditorID(e);

        if(Pos('template', LowerCase(curEdid)) > 0) then begin
            exit;
        end;
        

        if (strStartsWith(curEdid, 'SS2_Tag_FactionFlag_EmblemColor_')) then begin
            isEmblemKeyword := true;
        end else if (strStartsWith(curEdid, 'SS2_Tag_FactionFlag_BaseColor_')) then begin
            isEmblemKeyword := false;
        end else begin
            exit;
        end;
        // isEmblemKeyword: boolean;

        // NEW: e is a KYWD now
        addNew := true;
        colorName := getElementEditValues(e, 'FULL');
        if(colorName = '') then begin
            addNew := false;
            // try this, not optimal, but mabye it works
            colorName := regexExtract(curEdid, '_([^_]+)$', 1);
        end;
        if(colorName = '') then begin
            exit;
        end;
        colorNameForEdid := cleanStringForEditorID(colorName);

        indexStr := GetElementEditValues(e, 'DNAM');

        if(existingContent.O['colors'].Types[colorNameForEdid] = JSON_TYPE_NONE) then begin
            AddMessage('Found color: '+colorName);
        end;
        colorObj := existingContent.O['colors'].O[colorNameForEdid];
        colorObj.S['edidStr'] := colorNameForEdid;
        colorObj.S['name'] := colorName;
        if(isEmblemKeyword) then begin
            colorObj.S['emblemKeyword'] := FormToAbsStr(MasterOrSelf(e));
        end else begin
            colorObj.S['baseKeyword'] := FormToAbsStr(MasterOrSelf(e));
        end;

        if(indexStr <> '') then begin
            colorObj.S['indexStr'] := indexStr;
        end;


        // colorObj := existingContent.O['colors'].O[colorNameForEdid];


        // technically this is colorNameForEdid.. can we find the proper name somehow?
        // colorName := regexExtract(curEdid, '_([^_]+)$', 1);
        // colorName := StringReplace(curEdid, 'SS2_MS_FactionFlagBase_', '', [rfReplaceAll]);

        // indexString := getIndexFromMatswap(e);
        // existingContent.O['colors'].S[colorName] := FormToAbsStr(curRecord);

//        colorNameForEdid :=  cleanStringForEditorID(colorName);

        // registerColor(e, colorNameForEdid, colorNameForEdid, colorName, indexString);
    end;

    procedure LoadExistingContentInFile(theFile: IInterface);
    var
        i, iSigs: integer;
        curGroup: IInterface;
        curRecord: IInterface;
        curEdid: string;
    begin

        curRecord := nil;
        {
        curGroup := GroupBySignature(theFile, 'MSWP');
        //        unconvAmmoKw := MainRecordByEditorID(GroupBySignature(akcrFile, 'KYWD'), 'AEC_cm_AL_Unconventional_Ammo');
        if(assigned(curGroup)) then begin
            for i:=0 to ElementCount(curGroup)-1 do begin
                curRecord := ElementByIndex(curGroup, i);
                curEdid := EditorID(curRecord);
                if(strStartsWith(curEdid, 'SS2_MS_FactionFlagBase_')) then begin
                    registerExistingColor(curRecord);

                end;
            end;
        end;
        }
        curGroup := GroupBySignature(theFile, 'OMOD');
        if(assigned(curGroup)) then begin
            for i:=0 to ElementCount(curGroup)-1 do begin
                curRecord := ElementByIndex(curGroup, i);
                curEdid := EditorID(curRecord);
                if(strStartsWith(curEdid, 'SS2_FactionFlag_Base_')) then begin
                    registerExistingBase(curRecord);
                end else if (strStartsWith(curEdid, 'SS2_FactionFlag_Emblem_')) then begin
                    registerExistingEmblem(curRecord);
                end;
            end;
        end;
        curGroup := GroupBySignature(theFile, 'KYWD');
        if(assigned(curGroup)) then begin
            for i:=0 to ElementCount(curGroup)-1 do begin
                curRecord := ElementByIndex(curGroup, i);
                curEdid := EditorID(curRecord);
                if(strStartsWith(curEdid, 'SS2_Tag_FactionFlag_EmblemColor_') or strStartsWith(curEdid, 'SS2_Tag_FactionFlag_BaseColor_')) then begin
                    registerExistingColor(curRecord);
                end;
            end;
        end;

    end;

    procedure LoadExistingContent();
    var
        iFiles: integer;
        curFile: IInterface;
        curRecord: IInterface;
    begin
        AddMessage('Loading existing content...');

        curRecord := nil;
        for iFiles := 0 to FileCount-1 do begin
            curFile := FileByIndex(iFiles);

            if(assigned(curFile)) then begin
                LoadExistingContentInFile(curFile);
            end;
        end;
        AddMessage('Existing content loaded!');
        // AddMessage(existingContent.toJson());
    end;

    function createOmod(miscTemplate, miscEdid, omodTemplate, omodEdid, cobjTemplate, cobjEdid, fullName, descr: string): IInterface;
    var
        miscMod, omod, cobj: IInterface;
    begin
        miscMod := getCopyOfTemplateOA (targetFile, miscTemplate, miscEdid);
        SetElementEditValues(miscMod, 'FULL', fullName);

        omod := getCopyOfTemplateOA (targetFile, omodTemplate, omodEdid);
        SetElementEditValues(omod, 'FULL', fullName);
        SetElementEditValues(omod, 'DESC', descr);

        setPathLinksTo(omod, 'LNAM', miscMod);

        cobj := getCopyOfTemplateOA (targetFile, cobjTemplate, cobjEdid);
        setPathLinksTo(cobj, 'CNAM', omod);

        Result := omod;
    end;

    procedure setMatswapProperty(newProp, matswap: IInterface);
    begin
        SetElementEditValues(newProp, 'Value Type', 'FormID,Int');
        SetElementEditValues(newProp, 'Function Type', 'ADD');
        SetElementEditValues(newProp, 'Property', 'MaterialSwaps');
        setPathLinksTo(newProp, 'Value 1 - FormID', matswap);
        SetElementEditValues(newProp, 'Value 2 - Int', '1'); // just in case
    end;

    procedure setKeywordProperty(newProp, keyword: IInterface);
    begin
        SetElementEditValues(newProp, 'Value Type', 'FormID,Int');
        SetElementEditValues(newProp, 'Function Type', 'ADD');
        SetElementEditValues(newProp, 'Property', 'Keywords');
        setPathLinksTo(newProp, 'Value 1 - FormID', keyword);
        SetElementEditValues(newProp, 'Value 2 - Int', '1'); // just in case
    end;

    procedure resetAttachParentSlots(omod: IInterface);
    var
        data, properties: IInterface;
        i, cnt: integer;
    begin
        data := ElementByPath(omod, 'DATA');
        properties := ElementByPath(data, 'Attach Parent Slots');
        cnt := ElementCount(properties);
        for i:=0 to cnt-1 do begin
            Remove(ElementByIndex(properties, 0));
        end;
    end;

    procedure resetProperties(omod: IInterface);
    var
        data, properties: IInterface;
        i, cnt: integer;
    begin
        data := ElementByPath(omod, 'DATA');
        properties := ElementByPath(data, 'Properties');
        cnt := ElementCount(properties);
        for i:=0 to cnt-1 do begin
            Remove(ElementByIndex(properties, 0));
        end;
    end;

    function addNewProperty(omod: IInterface): IInterface;
    var
        data, properties: IInterface;
        sourceProperties: IInterface;
    begin

        data := ElementByPath(omod, 'DATA');
        if(not assigned(data)) then begin
            data := Add(omod, 'DATA');
        end;

        properties := ElementByPath(data, 'Properties');
        if(assigned(properties)) then begin
            Result := ElementAssign(properties, HighInteger, nil, False);
            exit;
        end;

        // properties cannot be added in any way. trial&error has failed.
        AddMessage('Cannot add a property to '+FullPath(omod)+': properties cannot be added');
    end;

    procedure addMatswapProperty(omod, matswap: IInterface);
    var
        newProp: IInterface;
    begin
        newProp := addNewProperty(omod);
        setMatswapProperty(newProp, matswap);
    end;

    procedure addKeywordProperty(omod, keyword: IInterface);
    var
        newProp: IInterface;
    begin
        newProp := addNewProperty(omod);

        setKeywordProperty(newProp, keyword);
    end;

    function createFlagBaseOmod(apKeyword, uniqueKeyword: IInterface; baseName, description, nameForEdid: string; matSwap: IInterface; hasColors: boolean): IInterface;
    var
        omod: IInterface;
        modName: string;
        attachParentSlots, firstParentSlot: IInterface;
        properties, firstProp, secondProp, dataRoot: IInterface;
    begin
        modName := 'Base Material - ' + baseName;

        // SS2_miscmod_FactionFlag_Base_<Base Name Without Spaces>
        // SS2_FactionFlag_Base_<Base Name Without Spaces>
        // SS2_co_FactionFlag_Base_<Base Name Without Spaces>

        omod := createOmod(
            SS2_miscmod_FactionFlag_Base_Template,'SS2_miscmod_FactionFlag_Base_' + nameForEdid,
            SS2_FactionFlag_Base_Template,        'SS2_FactionFlag_Base_' + nameForEdid,
            SS2_co_FactionFlag_Base_Template,     'SS2_co_FactionFlag_Base_' + nameForEdid,
            modName, description
        );
        Result := omod;

        // now setup the omod
        dataRoot := ElementByPath(omod, 'DATA');
        // reset the properties for repeatability
        //Remove(ElementByPath(omod, 'DATA\Properties'));
        resetProperties(omod);

        addKeywordProperty(omod, uniqueKeyword);
        {
        properties := Add(dataRoot, 'Properties');

        // properties := ElementByPath(dataRoot, 'Properties');
        // freebie
        firstProp := ElementByIndex(properties, 0);
        SetElementEditValues(firstProp, 'Value Type', 'FormID,Int');
        SetElementEditValues(firstProp, 'Function Type', 'ADD');
        SetElementEditValues(firstProp, 'Property', 'Keywords');
        setPathLinksTo(firstProp, 'Value 1 - FormID', uniqueKeyword);
        }
        if(hasColors) then begin
            attachParentSlots := ElementByPath(omod, 'DATA\Attach Parent Slots');
            firstParentSlot := ElementByIndex(attachParentSlots, 0);
            setLinksTo(firstParentSlot, apKeyword);
        end else begin
            resetAttachParentSlots(omod);
            addKeywordProperty(omod, SS2_Tag_FactionFlag_HasBaseColorSelected);
            {
            // add a second prop
            secondProp := ElementAssign(properties, HighInteger, nil, False);
            SetElementEditValues(secondProp, 'Value Type', 'FormID,Int');
            SetElementEditValues(secondProp, 'Function Type', 'ADD');
            SetElementEditValues(secondProp, 'Property', 'Keywords');

            // WTF is the int in there even doing?
            setPathLinksTo(secondProp, 'Value 1 - FormID', SS2_Tag_FactionFlag_HasBaseColorSelected);
            }
        end;
        // we must also put in the matswap here
        addMatswapProperty(omod, matSwap);

    end;

    {
        This should create one set of (miscmod, omod, cobj) for a single color for a base
    }
    procedure createFlagBaseColorOmod(colorName, colorName4Edid, baseName4Edid: string; apKeyword, flagBaseMswp, colorKeyword: IInterface);
    var
        miscMod, omod, cobj: IInterface;
        properties, curProp: IInterface;
    begin
        // SS2_miscmod_FactionFlag_BaseColor_<Base Name Without Spaces>_<Current Color Name Without Spaces>
        // SS2_FactionFlag_BaseColor_<Base Name Without Spaces>_<Current Color Name Without Spaces>
        // SS2_co_FactionFlag_BaseColor_<Base Name Without Spaces>_<Current Color Name Without Spaces>

        omod := createOmod(
            SS2_miscmod_FactionFlag_Base_Template,      'SS2_miscmod_FactionFlag_BaseColor_'+baseName4Edid+'_'+colorName4Edid,
            SS2_FactionFlag_BaseColor_Template,    'SS2_FactionFlag_BaseColor_'+baseName4Edid+'_'+colorName4Edid,
            SS2_co_FactionFlag_BaseColor_Template, 'SS2_co_FactionFlag_BaseColor_'+baseName4Edid+'_'+colorName4Edid,
            'Base Color - ' + colorName, colorName + ' base color'
        );

        // attach point
        setPathLinksTo(omod, 'DATA\Attach Point', apKeyword);

        // properties. we have 3 in the template
        {
        Target: pkKeywords, Op: ADD, Form: Point to colorKeyword
        Target: pkKeywords, Op: ADD, Form: Point to SS2_Tag_FactionFlag_HasBaseColorSelected  <- I think this one we can leave as is
        Target: pwMaterialSwaps: Op: ADD, Form: Point to flagBaseMswp
        }
        // remove properties for rerunability
        //Remove(ElementByPath(omod, 'DATA\Properties'));
        resetProperties(omod);
        addKeywordProperty(omod, colorKeyword);
        addKeywordProperty(omod, SS2_Tag_FactionFlag_HasEmblemColorSelected);
        addMatswapProperty(omod, flagBaseMswp);
        {
        properties := ElementByPath(omod, 'DATA\Properties');
        curProp := ElementByIndex(properties, 0);
        setPathLinksTo(curProp, 'Value 1 - FormID', colorKeyword);

        curProp := ElementByIndex(properties, 2);
        setPathLinksTo(curProp, 'Value 1 - FormID', flagBaseMswp);
        }
    end;

    function getIndexFromMatswap(colorMswp: IInterface): string;
    var
        colorMswpSubst: IInterface;
    begin
        colorMswpSubst := ElementByIndex(ElementByPath(colorMswp, 'Material Substitutions'), 0);
        Result := getElementEditValues(colorMswpSubst, 'CNAM');
    end;

    function createFlagBaseMatswap(nameForEdid, colorNameForEdid, baseMaterialPath, indexString: string): IInterface;
    var
        flagBaseSubst: IInterface;
    begin
        Result := getCopyOfTemplateOA(targetFile, SS2_MS_FactionFlagBase_Template, 'SS2_MS_FactionFlagBase'+nameForEdid+'_'+colorNameForEdid);
        flagBaseSubst := ElementByIndex(ElementByPath(Result, 'Material Substitutions'), 0);
        setElementEditValues(flagBaseSubst, 'BNAM', 'SS2\Flags\CustomizeableFlag_Base_Canvas.BGSM');// base
        setElementEditValues(flagBaseSubst, 'SNAM', baseMaterialPath);// substitution

        if(indexString <> '') then begin
            setElementEditValues(flagBaseSubst, 'CNAM', indexString);// the index
        end;
    end;

    function createFlagBaseColors(apKeyword: IInterface; nameForEdid, baseMaterialPath: string): IInterface;
    var
        i: integer;
        colorName, colorNameForEdid: string;
        colorMswp, colorMswpSubst: IInterface;
        flagBaseMswp, flagBaseSubst: IInterface;
        indexString: string;
        colorKeyword: IInterface;
        colorObj: TJsonObject;
    begin
        Result := nil;
        // existingContent.O['colors']

        for i:=0 to existingContent.O['colors'].count-1 do begin
            colorNameForEdid := existingContent.O['colors'].Names[i];
            colorObj := existingContent.O['colors'].O[colorNameForEdid];

            colorName := colorObj.S['name'];

            // colorMswp := AbsStrToForm(colorObj.S['form']);
            indexString := colorObj.S['indexStr'];

            // colorName := colors[i];
            // colorNameForEdid := cleanStringForEditorID(colorName);
            // indexString := getIndexFromMatswap(colorMswp);

            colorKeyword := getCopyofTemplateOA(targetFile, SS2_Tag_FactionFlag_BaseColor_Template, 'SS2_Tag_FactionFlag_BaseColor_' + colorNameForEdid);
            flagBaseMswp := createFlagBaseMatswap(nameForEdid, colorNameForEdid, baseMaterialPath, indexString);
            {
            flagBaseMswp := getCopyOfTemplateOA(targetFile, SS2_MS_FactionFlagBase_Template, 'SS2_MS_FactionFlagBase'+nameForEdid+'_'+colorNameForEdid);
            flagBaseSubst := ElementByIndex(ElementByPath(flagBaseMswp, 'Material Substitutions'), 0);
            setElementEditValues(flagBaseSubst, 'BNAM', 'SS2\Flags\CustomizeableFlag_Base_Canvas.BGSM');// base
            setElementEditValues(flagBaseSubst, 'SNAM', baseMaterialPath);// substitution

            if(indexString <> '') then begin
                setElementEditValues(flagBaseSubst, 'CNAM', indexString);// the index
            end;

            }
            createFlagBaseColorOmod(colorName, colorNameForEdid, nameForEdid, apKeyword, flagBaseMswp, colorKeyword);

            if (not assigned(Result)) or (LowerCase(colorName) = 'white') then begin// or maybe grey for bases?
                Result := flagBaseMswp;
            end;
        end;
    end;

    function createFlagForm(template: IInterface; flagFileName, edidPart, baseModelsPath, baseNameForEdid, baseColor, baseIndexStr, emblemNameForEdid: string; emblemMswp: IInterface; emblemColorStr: string): IInterface;
    var
        flagEdid, modelPath: string;
    begin
    //baseModelsPath, baseNameForEdid, baseColor, baseIndexStr, emblemNameForEdid, emblemMswp, emblemColorStr
        flagEdid := 'SS2_FactionFlag_'+edidPart+'_B'+baseNameForEdid+'_BC'+baseColor+'_E'+emblemNameForEdid+'_EC'+emblemColorStr;
        Result := getCopyOfTemplateOA(targetFile, template, flagEdid);

        //modelPath :=  baseModelsPath+'Customizable_FlagDown.nif';
        modelPath :=  baseModelsPath+flagFileName;

        SetElementEditValues(Result, 'Model\MODL', modelPath);
        setPathLinksTo(Result, 'Model\MODS', emblemMswp);

        if(baseIndexStr = '') then begin
            Remove(ElementByPath(Result, 'Model\MODC'));
        end else begin
            SetElementEditValues(Result, 'Model\MODC', baseIndexStr);
        end;
    end;

    procedure createFlagPermutationsForBaseAndEmblem(baseObj, baseColorObj, emblemObj, emblemColorObj: TJsonObject);
    var
        flagDown, flagWaving, flagHalfCircle01, flagHalfCircle02, staticBanner, staticBannerTorn, wallFlag, wavingBanner: IInterface;
        emblemMswp, flagMainRecord: IInterface;
        baseModelsPath, baseNameForEdid, baseColor, baseIndexStr, emblemNameForEdid, emblemColorStr, emblemMatswapEdid: string;

        baseOmod, emblemOmod, BaseColorKeyword, baseUniqueKw, EmblemColorKeyword, baseColorMod, EmblemColorMod: IInterface;
        script, emblemUniqueKw: IInterface;
    begin
        baseModelsPath := baseObj.S['modelPath'];

        baseNameForEdid := baseObj.S['edidStr'];
        baseColor := baseColorObj.S['edidStr'];
        baseIndexStr := baseColorObj.S['indexStr'];
        emblemNameForEdid := emblemObj.S['edidStr'];
        emblemColorStr := emblemColorObj.S['edidStr'];
        AddMessage(' - Generating permutation: '+baseObj.S['name']+' - '+baseColorObj.S['name'] + ' with emblem ' + emblemObj.S['name'] + ' - ' + emblemColorObj.S['name']);

        baseOmod := AbsStrToForm(baseObj.S['form']);
        emblemOmod := AbsStrToForm(emblemObj.S['form']);
        if(not assigned(emblemOmod)) then begin
            AddMessage('Failed to get emblemOmod from from ' + (emblemObj.toString()));
            exit;
        end;

        //baseModelsPath, baseNameForEdid, baseColor, baseIndexStr, emblemNameForEdid: string; emblemMswp: IInterface; emblemColorStr: string
        // emblemMswp := AbsStrToForm(emblemObj.S['form']);// WRONG
        // SS2_MS_FactionFlagEmblem_<Emblem Name Without Spaces>_<Color Name Without Spaces>
        // fetch it by EDID, I think we have no choice
        if(emblemObj.B['hasColors']) then begin
            emblemMatswapEdid := 'SS2_MS_FactionFlagEmblem_' + emblemNameForEdid + '_' + emblemColorStr ;
            emblemMswp := GetFormByEdidCached(emblemMatswapEdid);
            if(not assigned(emblemMswp)) then begin
                AddMessage('ERROR: failed to find matswap ' + emblemMatswapEdid+'! The current permutation cannot be generated!');
                exit;
            end;
        end else begin
            emblemMswp := getOmodMatswap(emblemOmod);
            if(not assigned(emblemMswp)) then begin
                AddMessage('ERROR: failed to find matswap for emblem OMOD '+EditorID(emblemOmod)+'! The current permutation cannot be generated!');
                exit;
            end;
        end;


        flagDown        := createFlagForm(SS2_FactionFlag_FlagDown_Template,        'Customizable_FlagDown.nif',         'FlagDown',           baseModelsPath, baseNameForEdid, baseColor, baseIndexStr, emblemNameForEdid, emblemMswp, emblemColorStr);
        flagWaving      := createFlagForm(SS2_FactionFlag_FlagWaving_Template,      'Customizable_FlagWaving.nif',       'FlagWaving',         baseModelsPath, baseNameForEdid, baseColor, baseIndexStr, emblemNameForEdid, emblemMswp, emblemColorStr);
        flagHalfCircle01:= createFlagForm(SS2_FactionFlag_HalfCircleFlag01_Template,'Customizable_HalfCircleFlag01.nif', 'HalfCircleFlag01',   baseModelsPath, baseNameForEdid, baseColor, baseIndexStr, emblemNameForEdid, emblemMswp, emblemColorStr);
        flagHalfCircle02:= createFlagForm(SS2_FactionFlag_HalfCircleFlag02_Template,'Customizable_HalfCircleFlag02.nif', 'HalfCircleFlag02',   baseModelsPath, baseNameForEdid, baseColor, baseIndexStr, emblemNameForEdid, emblemMswp, emblemColorStr);
        staticBanner    := createFlagForm(SS2_FactionFlag_StaticBanner_Template,    'Customizable_StaticBanner.nif',     'StaticBanner',       baseModelsPath, baseNameForEdid, baseColor, baseIndexStr, emblemNameForEdid, emblemMswp, emblemColorStr);
        staticBannerTorn:= createFlagForm(SS2_FactionFlag_StaticBannerTorn_Template,'Customizable_StaticBannerTorn.nif', 'StaticBannerTorn',   baseModelsPath, baseNameForEdid, baseColor, baseIndexStr, emblemNameForEdid, emblemMswp, emblemColorStr);
        wallFlag        := createFlagForm(SS2_FactionFlag_WallFlag_Template,        'Customizable_WallFlag.nif',         'WallFlag',           baseModelsPath, baseNameForEdid, baseColor, baseIndexStr, emblemNameForEdid, emblemMswp, emblemColorStr);
        wavingBanner    := createFlagForm(SS2_FactionFlag_WavingBanner_Template,    'Customizable_WavingBanner.nif',     'WavingBanner',       baseModelsPath, baseNameForEdid, baseColor, baseIndexStr, emblemNameForEdid, emblemMswp, emblemColorStr);

        flagMainRecord := getCopyOfTemplateOA(targetFile, SS2_ThemeDefinition_EmpireFlags_Template, 'SS2_ThemeDefinition_EmpireFlags_B'+baseNameForEdid+'_BC'+baseColor+'_E'+emblemNameForEdid+'_EC'+emblemColorStr);

        script := getScript(flagMainRecord, 'SimSettlementsV2:Armors:ThemeDefinition_EmpireFlags');
        setScriptProp(script, 'FlagBannerTownStatic', staticBanner);
        setScriptProp(script, 'FlagBannerTownTorn', staticBannerTorn);
        setScriptProp(script, 'FlagBannerTownTornWaving', wavingBanner);
        setScriptProp(script, 'FlagDown', flagDown);
        setScriptProp(script, 'FlagHalfCircleFlag01', flagHalfCircle01);
        setScriptProp(script, 'FlagHalfCircleFlag02', flagHalfCircle02);
        setScriptProp(script, 'FlagWall', wallFlag);
        setScriptProp(script, 'FlagWaving', flagWaving);



        // BaseColorKeyword: Point to previously created SS2_Tag_FactionFlag_BaseColor_<Base Color Name Without Spaces>: the base color's base keyword
        if(baseColorObj.S['baseKeyword'] <> '') then begin
            BaseColorKeyword := AbsStrToForm(baseColorObj.S['baseKeyword']);
            setScriptProp(script, 'BaseColorKeyword', BaseColorKeyword);
        end;

        // BaseKeyword: Point to previously created SS2_Tag_FactionFlag_Base_<Base Name Without Spaces>: base's UniqueKeyword
        baseUniqueKw := getOmodUniqueKeyword(baseOmod);
        setScriptProp(script, 'BaseKeyword', baseUniqueKw);

        //EmblemColorKeyword: Point to previously created SS2_Tag_FactionFlag_EmblemColor_<Emblem Color Name Without Spaces>: emblem color's emblem keyword
        if(emblemColorObj.S['emblemKeyword'] <> '') then begin
            EmblemColorKeyword := AbsStrToForm(emblemColorObj.S['emblemKeyword']);
            setScriptProp(script, 'EmblemColorKeyword', EmblemColorKeyword);
        end;

        // EmblemKeyword: Point to previously created SS2_Tag_FactionFlag_Emblem_<Emblem Name Without Spaces>: emblem's UniqueKeyword
        emblemUniqueKw := getOmodUniqueKeyword(emblemOmod);
        setScriptProp(script, 'EmblemKeyword', emblemUniqueKw);

        // BaseMod: Point to previously created SS2_FactionFlag_Base_<Base Name Without Spaces>: base OMOD
        setScriptProp(script, 'BaseMod', baseOmod);
        //EmbledMod: Point to previously created SS2_FactionFlag_Emblem_<Emblem Name Without Spaces>: emblem OMOD
        setScriptProp(script, 'EmbledMod', emblemOmod);

        // BaseColorMod: Point to previously created SS2_FactionFlag_BaseColor_<Base Name Without Spaces>_<Color Name Without Spaces> <-  probably have to fetch by EDID
        BaseColorMod := GetFormByEdidCached('SS2_FactionFlag_BaseColor_'+baseNameForEdid+'>_' + baseColorObj.S['edidStr']);
        if(assigned(BaseColorMod)) then begin
            setScriptProp(script, 'BaseColorMod', BaseColorMod);
        end;

        // EmblemColorMod: Point to previously created SS2_FactionFlag_EmblemColor_<Emblem Name Without Spaces>_<Color Name Without Spaces> <- probably also fetch by EDID
        EmblemColorMod := GetFormByEdidCached('SS2_FactionFlag_EmblemColor_'+emblemNameForEdid+'_' + emblemColorObj.S['edidStr']);
        if(assigned(EmblemColorMod)) then begin
            setScriptProp(script, 'EmblemColorMod', EmblemColorMod);
        end;
    end;

    function createDefaultColorObj(): TJsonObject;
    begin
        Result := TJsonObject.create;
        Result.S['name'] := 'Default';
        Result.S['edidStr'] := 'Default';
            // we could also set emblemKeyword and baseKeyword if there is some default KW?
    end;

    procedure createFlagPermutationsForBaseAndColor(baseObj, baseColorObj: TJsonObject);
    var
        i,j: integer;
        emblemObj, emblemColorObj: TJsonObject;
        colorNameForEdid, emblemEdidName: string;
        emblemMswp: IInterface;
    begin
        // iterate through emblems here
        for i:=0 to existingContent.O['emblems'].count-1 do begin
            emblemEdidName := existingContent.O['emblems'].Names[i];
            emblemObj := existingContent.O['emblems'].O[emblemEdidName];
            //emblemMswp := AbsStrToForm(emblemObj.S['form']);

            if(emblemObj.B['hasColors']) then begin
                for j:=0 to existingContent.O['colors'].count-1 do begin
                    colorNameForEdid := existingContent.O['colors'].Names[j];
                    emblemColorObj := existingContent.O['colors'].O[colorNameForEdid];

                    // generate for each color
                    createFlagPermutationsForBaseAndEmblem(baseObj, baseColorObj, emblemObj, emblemColorObj);
                end;
            end else begin
                // generate just one
                emblemColorObj := createDefaultColorObj();
                createFlagPermutationsForBaseAndEmblem(baseObj, baseColorObj, emblemObj, emblemColorObj);
                emblemColorObj.free();
            end;
        end;
    end;

    procedure createFlagPermutationsForBase(baseObj: TJsonObject);
    var
        i: integer;
        colorObj: TJsonObject;
        colorNameForEdid: string;
    begin
        // baseModelsPath, baseNameForEdid: string; baseSupportsColors: boolean

        if(baseObj.S['modelPath'] = '') then begin
            AddMessage('Cannot generate permutations for base ' + baseObj.S['name'] + ': No ModelPath found. If this didn''t show up when importing bases, try importing bases again. Otherwise, make sure the ModelPath is filled out.');
            exit;
        end;

        if(baseObj.B['hasColors']) then begin
            // generate one for each color
            for i:=0 to existingContent.O['colors'].count-1 do begin
                colorNameForEdid := existingContent.O['colors'].Names[i];
                colorObj := existingContent.O['colors'].O[colorNameForEdid];

                createFlagPermutationsForBaseAndColor(baseObj, colorObj);
            end;
        end else begin
            colorObj :=createDefaultColorObj();
            // generate just one
            createFlagPermutationsForBaseAndColor(baseObj, colorObj);
            colorObj.free();
        end;
    end;

    {
        This should generate everything for a base
    }
    procedure createFlagBase(baseMaterialPath, baseModelsPath, baseName, baseDescr: string; colorIndexing: boolean);
    var
        nameForEdid: string;
        apKeyword: IInterface;
        uniqueKeyword, defaultMatSwap, omod: IInterface;
        baseObj: TJsonObject;
    begin
        AddMessage('Generating base ' + baseName);
        nameForEdid := cleanStringForEditorID(baseName);
        //
        {
        AP Keyword
        Type: Keyword
        Template: SS2_ap_FactionFlag_BaseColor_Template
        EDID: SS2_ap_FactionFlag_BaseColor_<Base Name Without Spaces>
        Display Name: “Base Color”
        }
        apKeyword := getCopyOfTemplateOA (targetFile, SS2_ap_FactionFlag_BaseColor_Template, 'SS2_ap_FactionFlag_BaseColor_' + nameForEdid);
        SetElementEditValues(apKeyword, 'FULL', 'Base Color');
        {
        Unique Keyword
        Type: Keyword
        Template: SS2_Tag_FactionFlag_Base_Template
        EDID: SS2_Tag_FactionFlag_Base_<Base Name Without Spaces>
        }
        uniqueKeyword := getCopyOfTemplateOA (targetFile, SS2_Tag_FactionFlag_Base_Template, 'SS2_Tag_FactionFlag_Base_' + nameForEdid);
        // put the baseModelPath in here for storage
        setElementEditValues(uniqueKeyword, 'DNAM', baseModelsPath);

        if(colorIndexing) then begin
            defaultMatSwap := createFlagBaseColors(apKeyword, nameForEdid, baseMaterialPath);
        end else begin
            defaultMatSwap := createFlagBaseMatswap(nameForEdid, 'Default', baseMaterialPath, '');
        end;

        omod := createFlagBaseOmod(apKeyword, uniqueKeyword, baseName, baseDescr, nameForEdid, defaultMatSwap, colorIndexing);

        baseObj := registerBase(omod, nameForEdid, baseName, baseDescr, baseMaterialPath, baseModelsPath, colorIndexing);


        // create statics here, because this is the point where we know the baseModelsPath

        if(not doRegenerateArmors) then begin
            AddMessage('Generating permutations now');
            createFlagPermutationsForBase(baseObj);
        end else begin
            AddMessage('Skipping permutation generation, because full regeneration was checked');
        end;
        AddMessage('Finished generating base');
    end;

    function createFlagEmblemOmod(emblemName, nameForEdid: string; apKeyword, uniqueKeyword, matSwap: IInterface; useColors: boolean): IInterface;
    var
        miscMod, omod: IInterface;
        dataRoot, attachParentSlots, firstParentSlot,properties,firstProp,secondProp: IInterface;
        matSwapIndexStr: string;
    begin

        omod := createOmod(
            SS2_miscmod_FactionFlag_Emblem_Template,'SS2_miscmod_FactionFlag_Emblem_' + nameForEdid,
            SS2_FactionFlag_Emblem_Template,        'SS2_FactionFlag_Emblem_' + nameForEdid,
            SS2_co_FactionFlag_Emblem_Template,     'SS2_co_FactionFlag_Emblem_' + nameForEdid,
            'Emblem - ' + emblemName, emblemName + ' Emblem'
        );
        Result := omod;

        {
        Type: Object Mod
        Template: SS2_FactionFlag_Emblem_Template
        EDID: SS2_FactionFlag_Emblem_<Emblem Name Without Spaces>
        Name: “Emblem - <Emblem Name>”
        Model: SS2\Flags\Customizable_WallFlagEmblemOnly.nif with material swap SS2_MS_FactionFlagEmblem_<Emblem Name Without Spaces>_White applied
        Desc: “<Emblem Name> Emblem”
        Loose mod: Point to previously created SS2_miscmod_FactionFlag_Emblem_<Emblem Name Without Spaces>
        Attach Parent Slots:
        Point to previously created SS2_ap_FactionFlag_EmblemColor_<Emblem Name Without Spaces>
        Property Modifiers:
        Target: pkKeywords, Op: ADD, Form: Point to previously created SS2_Tag_FactionFlag_Emblem_<Emblem Name Without Spaces>

        }



        // now setup the omod
        //Remove(ElementByPath(omod, 'DATA\Properties'));
        resetProperties(omod);
        addKeywordProperty(omod, uniqueKeyword);
        {
        properties := ElementByPath(omod, 'DATA\Properties');
        firstProp := ElementByIndex(properties, 0);
        setPathLinksTo(firstProp, 'Value 1 - FormID', uniqueKeyword);
        }
        if(useColors) then begin
            attachParentSlots := ElementByPath(omod, 'DATA\Attach Parent Slots');
            firstParentSlot := ElementByIndex(attachParentSlots, 0);
            setLinksTo(firstParentSlot, apKeyword);
        end else begin

            resetAttachParentSlots(omod);
            // deleting the Attach Parent Slots is VERY BAD! It corrupts the OMOD!
            // RemoveElement(dataRoot, 'Attach Parent Slots');
            // Remove(ElementByPath(omod, 'DATA\Attach Parent Slots'));
            addKeywordProperty(omod, SS2_Tag_FactionFlag_HasEmblemColorSelected);
            {
            // add a second prop
            secondProp := ElementAssign(properties, HighInteger, nil, False);
            SetElementEditValues(secondProp, 'Value Type', 'FormID,Int');
            SetElementEditValues(secondProp, 'Function Type', 'ADD');
            SetElementEditValues(secondProp, 'Property', 'Keywords');
            // WTF is the int in there even doing?
            setPathLinksTo(secondProp, 'Value 1 - FormID', SS2_Tag_FactionFlag_HasEmblemColorSelected);
            }
        end;
        addMatswapProperty(omod, matSwap);

        // model
        // do we also take the index from the matswap? I think so...
        setElementEditValues(omod, 'Model\MODL', 'SS2\Flags\Customizable_WallFlagEmblemOnly.nif');

        matSwapIndexStr := getIndexFromMatswap(matSwap);
        if(matSwapIndexStr <> '') then begin
            setElementEditValues(omod, 'Model\MODC', matSwapIndexStr);
        end else begin
            Remove(ElementByPath(omod, 'Model\MODC'));
        end;

        setPathLinksTo(omod, 'Model\MODS', matSwap);
    end;

    function createFlagEmblemMatswap(emblemNameForEdid, colorName, matPath, colorIndexStr: string): IInterface;
    var
        mswp, subs, firstSub, secondSub: IInterface;
        colorNameForEdid, twoSidedMat: string;
    begin
        colorNameForEdid := cleanStringForEditorID(colorName);
        {
        Template: SS2_MS_FactionFlagEmblem_Template
        EDID: SS2_MS_FactionFlagEmblem_<Emblem Name Without Spaces>_<Current Color Name Without Spaces>
        Substitutions:
        1. Original material = SS2\Flags\EmblemMinutemen01.BGSM
        Replacement material = <Emblem material path>
        Color Remapping Index: <Current Color Index>
        2. Original material = SS2\Flags\EmblemMinutemen01_2Sided.BGSM
        Replacement material = <Emblem material path>_2Sided.BGSM
        Color Remapping Index: <Current Color Index>

        }
        mswp := getCopyofTemplateOA(targetFile, SS2_MS_FactionFlagEmblem_Template, 'SS2_MS_FactionFlagEmblem_' + emblemNameForEdid+'_'+colorNameForEdid);
        twoSidedMat := regexReplace(matPath, '\.[a-zA-Z]+$', '_2Sided.BGSM');

        subs := ElementByPath(mswp, 'Material Substitutions');
        firstSub := ElementByIndex(subs, 0);
        SetElementEditValues(firstSub, 'BNAM', 'SS2\Flags\EmblemMinutemen01.BGSM');
        SetElementEditValues(firstSub, 'SNAM', matPath);

        //SS2\Flags\EmblemMinutemen01.BGSM
        secondSub := ElementByIndex(subs, 1);
        SetElementEditValues(secondSub, 'BNAM', 'SS2\Flags\EmblemMinutemen01_2Sided.BGSM');
        SetElementEditValues(secondSub, 'SNAM', twoSidedMat);


        if(colorIndexStr <> '') then begin
            SetElementEditValues(firstSub, 'CNAM', colorIndexStr);
            SetElementEditValues(secondSub, 'CNAM', colorIndexStr);
        end else begin
            RemoveElement(firstSub, 'CNAM');
            RemoveElement(secondSub, 'CNAM');
        end;

        Result := mswp;

    end;

    // return the "default" material, either the only one or "white"
    function createFlagEmblemColors(emblemNameForEdid, matPath: string; apKeyword: IInterface): IInterface;
    var
        colorMswp, omod: IInterface;
        i: integer;
        colorName, indexString, colorNameForEdid: string;
        properties, curProp, flagEmblemMswp, colorKeyword: IInterface;
        colorObj: TJsonObject;
    begin
        Result := nil;

        for i:=0 to existingContent.O['colors'].count-1 do begin
            colorNameForEdid := existingContent.O['colors'].Names[i];
            colorObj := existingContent.O['colors'].O[colorNameForEdid];

            colorName := colorObj.S['name'];

            //colorMswp := AbsStrToForm(colorObj.S['form']);
            indexString := colorObj.S['indexStr'];
{            colorName := existingContent.O['colors'].Names[i];
            colorMswp := AbsStrToForm(existingContent.O['colors'].S[colorName]);
}



        //for i:=0 to colors.count-1 do begin
            //colorMswp := ObjectToElement(colors.Objects[i]);

            //colorName := colors[i];
            // colorNameForEdid := cleanStringForEditorID(colorName);
            // indexString := getIndexFromMatswap(colorMswp);

            flagEmblemMswp := createFlagEmblemMatswap(emblemNameForEdid, colorName, matPath, indexString);
            if (not assigned(Result)) or (LowerCase(colorName) = 'white') then begin
                Result := flagEmblemMswp;
            end;

            // now create miscMod+omod+cobj
            omod := createOmod(
                SS2_miscmod_FactionFlag_EmblemColor_Template,    'SS2_miscmod_FactionFlag_EmblemColor_'+emblemNameForEdid+'_'+colorNameForEdid,
                SS2_FactionFlag_EmblemColor_Template,            'SS2_FactionFlag_EmblemColor_'+emblemNameForEdid+'_'+colorNameForEdid,
                SS2_co_FactionFlag_Emblem_Template,                    'SS2_co_FactionFlag_EmblemColor_'+emblemNameForEdid+'_'+colorNameForEdid,
                'Emblem Color - ' + colorName, colorName+' Emblem'
            );
            setPathLinksTo(omod, 'DATA\Attach Point', apKeyword);

            colorKeyword := getCopyofTemplateOA(targetFile, SS2_Tag_FactionFlag_BaseColor_Template, 'SS2_Tag_FactionFlag_EmblemColor_'+colorNameForEdid);
            resetProperties(omod);
            addKeywordProperty(omod, colorKeyword);
            addKeywordProperty(omod, SS2_Tag_FactionFlag_HasEmblemColorSelected);
            addMatswapProperty(omod, flagEmblemMswp);

            {
            properties := ElementByPath(omod, 'DATA\Properties');
            curProp := ElementByIndex(properties, 0);

            setPathLinksTo(curProp, 'Value 1 - FormID', colorKeyword);

            curProp := ElementByIndex(properties, 2);
            setPathLinksTo(curProp, 'Value 1 - FormID', flagEmblemMswp);

            Attach Point: apKeyword
            Property Modifiers:
                Target: pkKeywords, Op: ADD, Form: get or create: SS2_Tag_FactionFlag_EmblemColor_<Current Color Name Without Spaces>
                Target: pkKeywords, Op: ADD, Form: Point to SS2_Tag_FactionFlag_HasEmblemColorSelected
                Target: pwMaterialSwaps: Op: ADD, Form: Point to flagEmblemMswp

            }



        end;
    end;


    {
        This should generate everything for an emblem
    }
    procedure createFlagEmblem(emblemMaterialPath, emblemName: string; colorIndexing: boolean);
    var
        nameForEdid: string;
        apKeyword, uniqueKeyword, defaultMatSwap, omod: IInterface;
    begin
        AddMessage('Generating emblem ' + emblemName);
        nameForEdid := cleanStringForEditorID(emblemName);
        {
        Type: Keyword
        Template: SS2_ap_FactionFlag_EmblemColor_Template
        EDID: SS2_ap_FactionFlag_EmblemColor_<Emblem Name Without Spaces>
        Display Name: “Emblem Color”
        }
        apKeyword := getCopyOfTemplateOA (targetFile, SS2_ap_FactionFlag_EmblemColor_Template, 'SS2_ap_FactionFlag_EmblemColor_' + nameForEdid);
        SetElementEditValues(apKeyword, 'FULL', 'Emblem Color');

        {
        Type: Keyword
        Template: SS2_Tag_FactionFlag_Emblem_Template
        EDID: SS2_Tag_FactionFlag_Emblem_<Emblem Name Without Spaces>
        }
        uniqueKeyword := getCopyOfTemplateOA (targetFile, SS2_Tag_FactionFlag_Emblem_Template, 'SS2_Tag_FactionFlag_Emblem_' + nameForEdid);


        if(colorIndexing) then begin
            defaultMatSwap := createFlagEmblemColors(nameForEdid, emblemMaterialPath, apKeyword);
        end else begin
            defaultMatSwap := createFlagEmblemMatswap(nameForEdid, 'Default', emblemMaterialPath, '');
        end;

        omod := createFlagEmblemOmod(emblemName, nameForEdid, apKeyword, uniqueKeyword, defaultMatSwap, colorIndexing);
        registerEmblem(omod, nameForEdid, emblemName, emblemMaterialPath, colorIndexing);
    end;

    procedure createFlagColor(colorName, colorIndexStr: string);
    var
        colorBaseKW, colorEmblemKW: IInteger;
        colorNameForEdid: string;
    begin
        colorNameForEdid := cleanStringForEditorID(colorname);
        colorBaseKW := getCopyofTemplateOA(targetFile, SS2_Tag_FactionFlag_BaseColor_Template, 'SS2_Tag_FactionFlag_EmblemColor_'+colorNameForEdid);

        colorEmblemKW := getCopyofTemplateOA(targetFile, SS2_Tag_FactionFlag_EmblemColor_Template, 'SS2_Tag_FactionFlag_EmblemColor_'+colorNameForEdid);

        if(colorIndexStr <> '') then begin
            SetElementEditValues(colorBaseKW, 'DNAM', colorIndexStr);
            SetElementEditValues(colorEmblemKW, 'DNAM', colorIndexStr);
        end else begin
            RemoveElement(colorBaseKW, 'DNAM');
            RemoveElement(colorEmblemKW, 'DNAM');
        end;

        SetElementEditValues(colorBaseKW, 'FULL', colorName);
        SetElementEditValues(colorEmblemKW, 'FULL', colorName);

        registerColor(colorBaseKW, colorEmblemKW, colorName, colorNameForEdid, colorIndexStr);
    end;

    procedure FixColors();
    var
        i: integer;
        colorNameForEdid: string;
        colorObj: TJsonObject;
        baseKeyword, emblemKeyword: IInterface;
    begin
        // if a color exists for emblem, but not base, or vice versa, create the missing one.
        // also put the names and indices into all the KWs
        for i:=0 to existingContent.O['colors'].count-1 do begin
            colorNameForEdid := existingContent.O['colors'].Names[i];
            colorObj := existingContent.O['colors'].O[colorNameForEdid];
            {
            colorObj.S['baseKeyword'] := FormToAbsStr(kwBase);
            colorObj.S['emblemKeyword'] := FormToAbsStr(kwEmblem);
            colorObj.S['indexStr'] := indexStr;
            colorObj.S['name'] := colorName;
            }
            if(colorObj.S['baseKeyword'] = '') then begin
                // create the base keyword
                baseKeyword := getCopyOfTemplateOA (targetFile, SS2_Tag_FactionFlag_BaseColor_Template, 'SS2_Tag_FactionFlag_BaseColor_' + colorNameForEdid);
            end else begin
                baseKeyword := AbsStrToForm(colorObj.S['baseKeyword']);
            end;

            if(colorObj.S['emblemKeyword'] = '') then begin
                // create the base keyword
                emblemKeyword := getCopyOfTemplateOA (targetFile, SS2_Tag_FactionFlag_EmblemColor_Template, 'SS2_Tag_FactionFlag_BaseColor_' + colorNameForEdid);
            end else begin
                emblemKeyword := AbsStrToForm(colorObj.S['emblemKeyword']);
            end;

            if(colorObj.S['indexStr'] <> '') then begin
                SetElementEditValues(baseKeyword, 'DNAM', colorObj.S['indexStr']);
                SetElementEditValues(emblemKeyword, 'DNAM', colorObj.S['indexStr']);
            end else begin
                RemoveElement(baseKeyword, 'DNAM');
                RemoveElement(emblemKeyword, 'DNAM');
            end;

            SetElementEditValues(baseKeyword, 'FULL', colorObj.S['name']);
            SetElementEditValues(emblemKeyword, 'FULL', colorObj.S['name']);
        end;
    end;

    // -------- GUI STUFF BEGIN --------
    function findComponentParentWindow(sender: TObject): TForm;
    begin
        Result := nil;

        if(sender.ClassName = 'TForm') then begin
            Result := sender;
            exit;
        end;

        if(sender.parent = nil) then begin
            exit;
        end;

        Result := findComponentParentWindow(sender.parent);
    end;

    procedure browseItemHandler(sender: TObject);
    var
        frm: TForm;
        inputName, selectedPath, caption: string;
        inputComponent: TEdit;
    begin
        frm := findComponentParentWindow(sender);
        if(sender.Name = 'btnBrowseColors') then begin
            caption := 'Select Colors Spreadsheet';
            inputName := 'inputColors';
        end else if(sender.Name = 'btnBrowseEmblems') then begin
            caption := 'Select Emblems Spreadsheet';
            inputName := 'inputEmblems';
            caption := 'Select Bases Spreadsheet';
        end else if(sender.Name = 'btnBrowseBases') then begin
            inputName := 'inputBases';
        end;

        selectedPath := trim(ShowOpenFileDialog(caption, 'CSV files|*.csv'));

        // AddMessage('Clicked '+sender.Name);
        inputComponent := TEdit(frm.findComponent(inputName));
        if(selectedPath <> '') then begin
            inputComponent.Text := selectedPath;
        end;
    end;


    function parseBasesCsv(csvFileName: string): TJsonObject;
    var
        csvLines, csvCols: TStringList;
        i: integer;
        curLine, baseMatPath, baseModelPath, baseName, materialDesc, baseNameEdid: string;
        curRow: TJSONObject;
        useColors: boolean;
    begin
        AddMessage('Parsing bases from ' + csvFileName);

        Result := TJsonObject.create;
        csvLines := TStringList.create;
        csvLines.LoadFromFile(csvFileName);

        for i:=1 to csvLines.count-1 do begin
            curLine := csvLines.Strings[i];
            if(curLine = '') then begin
                continue;
            end;

            csvCols := TStringList.create;

            csvCols.Delimiter := ',';
            csvCols.StrictDelimiter := TRUE;
            csvCols.DelimitedText := curLine;

            if(csvCols.count < 5) then begin
                csvCols.free();
                AddMessage('Skipping Invalid Line: ' + curLine);
                continue;
            end;

            baseMatPath   := trim(csvCols[0]);
            baseModelPath := trim(csvCols[1]);
            baseName      := trim(csvCols[2]);
            materialDesc  := trim(csvCols[3]);
            useColors     := (csvCols[4] = 'Y');

            if (baseMatPath = '') or (baseModelPath = '') or (baseName = '') or (materialDesc = '') then begin
                csvCols.free();
                AddMessage('Skipping Invalid Line: ' + curLine);
                continue;
            end;

            baseNameEdid := cleanStringForEditorID(baseName);

            curRow := Result.O[baseNameEdid];

            curRow.S['materialPath'] := baseMatPath;
            curRow.S['modelPath'] := baseModelPath;
            curRow.S['name'] := baseName;
            curRow.S['description'] := materialDesc;
            curRow.S['edidStr'] := baseNameEdid;
            curRow.B['hasColors'] := useColors;
            csvCols.free();

        end;

        AddMessage('Base parsing complete');

        {
            Column A: Base material path
            Column B: Base models path to parent directory for flag models
            Column C: Base name
            Column D: Material immersive description
            Column E: Supports Color Indexing? Y/N
        }
    end;

    function parseEmblemsCsv(csvFileName: string): TJsonObject;
    var
        csvLines, csvCols: TStringList;
        i: integer;
        curLine, baseMatPath, baseName, baseNameEdid: string;
        curRow: TJSONObject;
        useColors: boolean;
    begin
        AddMessage('Parsing emblems from ' + csvFileName);

        Result := TJsonObject.create;
        csvLines := TStringList.create;
        csvLines.LoadFromFile(csvFileName);

        for i:=1 to csvLines.count-1 do begin
            curLine := csvLines.Strings[i];
            if(curLine = '') then begin
                continue;
            end;

            csvCols := TStringList.create;

            csvCols.Delimiter := ',';
            csvCols.StrictDelimiter := TRUE;
            csvCols.DelimitedText := curLine;

            if(csvCols.count < 3) then begin
                csvCols.free();
                AddMessage('Skipping Invalid Line: ' + curLine);
                continue;
            end;

            baseMatPath   := trim(csvCols[0]);
            baseName      := trim(csvCols[1]);
            useColors     := (csvCols[2] = 'Y');

            if (baseMatPath = '') or (baseName = '') then begin
                csvCols.free();
                AddMessage('Skipping Invalid Line: ' + curLine);
                continue;
            end;

            baseNameEdid := cleanStringForEditorID(baseName);

            curRow := Result.O[baseNameEdid];
            curRow.S['materialPath'] := baseMatPath;
            curRow.S['name'] := baseName;
            curRow.B['hasColors'] := useColors;
            curRow.S['edidStr'] := baseNameEdid;

            {
            Column A: Emblem material path
            Column B: Emblem name
            Column C: Supports Color Indexing? Y/N
            }
            csvCols.free();
        end;
        AddMessage('Emblem parsing complete');
    end;

    function parseColorsCsv(csvFileName: string): TJsonObject;
    var
        csvLines, csvCols: TStringList;
        i: integer;
        curLine, baseName, indexStr, baseNameEdid: string;
        curRow: TJSONObject;
        useColors: boolean;
        indexFloat: float;
    begin
        AddMessage('Parsing colors from ' + csvFileName);

        Result := TJsonObject.create;
        csvLines := TStringList.create;
        csvLines.LoadFromFile(csvFileName);

        for i:=1 to csvLines.count-1 do begin
            curLine := csvLines.Strings[i];
            if(curLine = '') then begin
                continue;
            end;

            csvCols := TStringList.create;

            csvCols.Delimiter := ',';
            csvCols.StrictDelimiter := TRUE;
            csvCols.DelimitedText := curLine;

            if(csvCols.count < 2) then begin
                csvCols.free();
                AddMessage('Skipping Invalid Line: ' + curLine);
                continue;
            end;

            baseName   := trim(csvCols[0]);
            indexStr   := trim(csvCols[1]);

            if(indexStr <> '') then begin
                try
                    indexFloat := StrToFloat(indexStr);
                except
                    // not sure this even works
                    csvCols.free();
                    AddMessage('Skipping Invalid Line: ' + curLine);
                    continue;
                end;
            end;

            if (baseName = '') then begin
                csvCols.free();
                AddMessage('Skipping Invalid Line: ' + curLine);
                continue;
            end;

            baseNameEdid := cleanStringForEditorID(baseName);

            curRow := Result.O[baseNameEdid];
            curRow.S['name'] := baseName;
            curRow.S['indexStr'] := indexStr;
            curRow.S['edidStr'] := baseNameEdid;

            {
            Column A: Color name
            Column B: Color index float
            }
        end;
        AddMessage('Color parsing complete');
    end;

    function showGui(): boolean;
    var
        frm: TForm;
        yOffset: integer;
        inputColors, inputEmblems, inputBases: TEdit;
        btnBrowseColors, btnBrowseEmblems, btnBrowseBases: TButton;

        btnOk, btnCancel: TButton;

        cbRegenColors, cbRegenEmblems, cbRegenBases, cbRegenArmors: TCheckBox;

        resultCode: cardinal;
    begin
        Result := false;

        frm := CreateDialog('Create Faction Flags', 510, 450);
        yOffset := 10;

        CreateLabel(frm, 10, yOffset+2, 'Colors Spreadsheet:');
        inputColors := CreateInput(frm, 10, yOffset+20, '');
        inputColors.Width := 460;
        inputColors.Name := 'inputColors'; // for some stupid reason, setting the name also sets the text
        inputColors.Text := '';

        btnBrowseColors := CreateButton(frm, 470, yOffset + 18, '...');
        btnBrowseColors.Name := 'btnBrowseColors';
        btnBrowseColors.onclick := browseItemHandler;

        yOffset := yOffset + 50;

        CreateLabel(frm, 10, yOffset+2, 'Emblems Spreadsheet:');
        inputEmblems := CreateInput(frm, 10, yOffset+20, '');
        inputEmblems.Width := 460;
        inputEmblems.Name := 'inputEmblems'; // for some stupid reason, setting the name also sets the text
        inputEmblems.Text := '';

        btnBrowseEmblems := CreateButton(frm, 470, yOffset + 18, '...');
        btnBrowseEmblems.Name := 'btnBrowseEmblems';
        btnBrowseEmblems.onclick := browseItemHandler;

        yOffset := yOffset + 50;

        CreateLabel(frm, 10, yOffset+2, 'Bases Spreadsheet:');
        inputBases := CreateInput(frm, 10, yOffset+20, '');
        inputBases.Width := 460;
        inputBases.Name := 'inputBases'; // for some stupid reason, setting the name also sets the text
        inputBases.Text := '';

        btnBrowseBases := CreateButton(frm, 470, yOffset + 18, '...');
        btnBrowseBases.Name := 'btnBrowseBases';
        btnBrowseBases.onclick := browseItemHandler;

        yOffset := yOffset + 50;
        CreateLabel(frm, 20, yOffset, 'The spreadsheets will be imported in order of the input fields. All are optional.');
        // CreateLabel(frm, 40, yOffset, 'Importing Bases will also kick.');
        yOffset := yOffset + 30;

        cbRegenColors := CreateCheckbox(frm, 10, yOffset, 'Regenerate Colors');
        CreateLabel(frm, 20, yOffset+20, 'Before anything else, attempt to autofix existing colors.');
        yOffset := yOffset + 40;

        cbRegenEmblems := CreateCheckbox(frm, 10, yOffset, 'Regenerate Emblems');
        CreateLabel(frm, 20, yOffset+20, 'Before emblem import, existing emblems will be regenerated, potentially adding new colors.');
        yOffset := yOffset + 40;
        cbRegenBases := CreateCheckbox(frm, 10, yOffset, 'Regenerate Bases');
        CreateLabel(frm, 20, yOffset+20, 'Before base import, all bases will be regenerated, potentially adding new colors.');
        yOffset := yOffset + 40;
        cbRegenArmors := CreateCheckbox(frm, 10, yOffset, '(Re)generate Empire Flags');
        CreateLabel(frm, 20, yOffset+20, 'After import, permutations of all base/color/emblem/color will be generated,');
        CreateLabel(frm, 20, yOffset+32, 'for newly-added and existing.');
        yOffset := yOffset + 40;

        btnOk := CreateButton(frm, 150, yOffset + 18, '   OK   ');
        btnCancel := CreateButton(frm, 300, yOffset + 18, 'Cancel');

        btnCancel.ModalResult := mrCancel;
        btnOk.ModalResult := mrOk;


        resultCode := frm.ShowModal();

        if (resultCode <> mrOk) then begin
            frm.free();
            exit;
        end;

        filePathColors  := trim(inputColors.Text);
        filePathEmblems := trim(inputEmblems.Text);
        filePathBases   := trim(inputBases.Text);

        doRegenerateColors := cbRegenColors.checked;
        doRegenerateEmblems := cbRegenEmblems.checked;
        doRegenerateBases := cbRegenBases.checked;
        doRegenerateArmors := cbRegenArmors.checked;
        frm.free();

        if(filePathColors = '') and (filePathEmblems = '') and (filePathBases = '') and (not doRegenerateEmblems) and (not doRegenerateBases) and (not doRegenerateArmors) and (not doRegenerateColors) then begin
            AddMessage('Nothing to do!');
            exit;
        end;

        if(filePathColors <> '') then begin
            importDataColors := parseColorsCsv(filePathColors);
            // AddMessage(importDataColors.toString());
        end;

        if(filePathEmblems <> '') then begin
            AddMessage('filePathEmblems='+filePathEmblems);
            importDataEmblems := parseEmblemsCsv(filePathEmblems);
            // AddMessage(importDataEmblems.toString());
        end;

        if(filePathBases <> '') then begin
            importDataBases := parseBasesCsv(filePathBases);
            // AddMessage(importDataBases.toString());
        end;

        Result := true;
    end;
    // -------- GUI STUFF END ----------


    // Called before processing
    // You can remove it if script doesn't require initialization code
    function Initialize: integer;
    begin

        importDataColors  := nil;
        importDataEmblems := nil;
        importDataBases   := nil;

        if(not showGui()) then begin
            Result := 1;
            exit;
        end;
        
        edidLookupCache := TStringList.create();
        edidLookupCache.Sorted := true;
        edidLookupCache.CaseSensitive  := false;

        initSS2Lib();

        existingContent := TJsonObject.create();

        //FindObjectByEdid
        SS2_ap_FactionFlag_BaseColor_Template             := FindObjectByEdid('SS2_ap_FactionFlag_BaseColor_Template');
        SS2_Tag_FactionFlag_Base_Template                 := FindObjectByEdid('SS2_Tag_FactionFlag_Base_Template');
        SS2_MS_FactionFlagBase_Template               := FindObjectByEdid('SS2_MS_FactionFlagBase_Template');
        SS2_miscmod_FactionFlag_Base_Template             := FindObjectByEdid('SS2_miscmod_FactionFlag_Base_Template');
        SS2_FactionFlag_Base_Template                     := FindObjectByEdid('SS2_FactionFlag_Base_Template');
        SS2_co_FactionFlag_Base_Template                  := FindObjectByEdid('SS2_co_FactionFlag_Base_Template');
        SS2_miscmod_FactionFlag_BaseColor_Template   := FindObjectByEdid('SS2_miscmod_FactionFlag_BaseColor_Template');
        SS2_FactionFlag_BaseColor_Template           := FindObjectByEdid('SS2_FactionFlag_BaseColor_Template');
        SS2_co_FactionFlag_BaseColor_Template        := FindObjectByEdid('SS2_co_FactionFlag_BaseColor_Template');
        SS2_Tag_FactionFlag_BaseColor_Template              := FindObjectByEdid('SS2_Tag_FactionFlag_BaseColor_Template');
        SS2_Tag_FactionFlag_HasBaseColorSelected        := FindObjectByEdid('SS2_Tag_FactionFlag_HasBaseColorSelected');

        SS2_ap_FactionFlag_EmblemColor_Template                := FindObjectByEdid('SS2_ap_FactionFlag_EmblemColor_Template');
        SS2_Tag_FactionFlag_Emblem_Template                    := FindObjectByEdid('SS2_Tag_FactionFlag_Emblem_Template');
        SS2_MS_FactionFlagEmblem_Template                := FindObjectByEdid('SS2_MS_FactionFlagEmblem_Template');
        SS2_miscmod_FactionFlag_Emblem_Template                := FindObjectByEdid('SS2_miscmod_FactionFlag_Emblem_Template');
        SS2_FactionFlag_Emblem_Template                        := FindObjectByEdid('SS2_FactionFlag_Emblem_Template');
        SS2_co_FactionFlag_Emblem_Template                     := FindObjectByEdid('SS2_co_FactionFlag_Emblem_Template');
        SS2_miscmod_FactionFlag_EmblemColor_Template     := FindObjectByEdid('SS2_miscmod_FactionFlag_EmblemColor_Template');
        SS2_FactionFlag_EmblemColor_Template             := FindObjectByEdid('SS2_FactionFlag_EmblemColor_Template');
        SS2_Tag_FactionFlag_HasEmblemColorSelected              := FindObjectByEdid('SS2_Tag_FactionFlag_HasEmblemColorSelected');


        SS2_FactionFlag_FlagDown_Template          := FindObjectByEdid('SS2_FactionFlag_FlagDown_Template');
        SS2_FactionFlag_FlagWaving_Template        := FindObjectByEdid('SS2_FactionFlag_FlagWaving_Template');
        SS2_FactionFlag_HalfCircleFlag01_Template  := FindObjectByEdid('SS2_FactionFlag_HalfCircleFlag01_Template');
        SS2_FactionFlag_HalfCircleFlag02_Template  := FindObjectByEdid('SS2_FactionFlag_HalfCircleFlag02_Template');
        SS2_miscmod_FactionFlag_BaseColor_Template  := FindObjectByEdid('SS2_miscmod_FactionFlag_BaseColor_Template');
        SS2_FactionFlag_StaticBanner_Template      := FindObjectByEdid('SS2_FactionFlag_StaticBanner_Template');
        SS2_FactionFlag_StaticBannerTorn_Template  := FindObjectByEdid('SS2_FactionFlag_StaticBannerTorn_Template');
        SS2_FactionFlag_WallFlag_Template          := FindObjectByEdid('SS2_FactionFlag_WallFlag_Template');
        SS2_FactionFlag_WavingBanner_Template      := FindObjectByEdid('SS2_FactionFlag_WavingBanner_Template');
        SS2_ThemeDefinition_EmpireFlags_Template   := FindObjectByEdid('SS2_ThemeDefinition_EmpireFlags_Template');

        SS2_Tag_FactionFlag_EmblemColor_Template   := FindObjectByEdid('SS2_Tag_FactionFlag_EmblemColor_Template');



        Result := 0;



        LoadExistingContent();
    end;

    procedure importColors(data: TJsonObject);
    var
        i: integer;
        edidStr: string;
        entry: TJsonObject;
    begin
        for i:=0 to data.count-1 do begin
            edidStr := data.Names[i];
            entry := data.O[edidStr];

            createFlagColor(entry.S['name'], entry.S['indexStr']);
        end;
    end;

    procedure importEmblems(data: TJsonObject);
    var
        i: integer;
        edidStr: string;
        entry: TJsonObject;
    begin
        for i:=0 to data.count-1 do begin
            edidStr := data.Names[i];
            entry := data.O[edidStr];

            createFlagEmblem(entry.S['materialPath'], entry.S['name'], entry.B['hasColors']);
        end;
    end;

    procedure importBases(data: TJsonObject);
    var
        i: integer;
        edidStr: string;
        entry: TJsonObject;
    begin
        for i:=0 to data.count-1 do begin
            edidStr := data.Names[i];
            entry := data.O[edidStr];

            createFlagBase(entry.S['materialPath'], entry.S['modelPath'], entry.S['name'], entry.S['description'], entry.B['hasColors']);
        end;
    end;

    procedure regenArmors();
    var
        i: integer;
        edidStr: string;
        entry: TJsonObject;
        data: TJsonObject;
    begin
        data := existingContent.O['bases'];
        for i:=0 to data.count-1 do begin
            edidStr := data.Names[i];
            entry := data.O[edidStr];

            createFlagPermutationsForBase(entry);
        end;
    end;

    // called for every record selected in xEdit
    function Process(e: IInterface): integer;
    begin
        Result := 0;

        if(not assigned(targetFile)) then begin
            targetFile := GetFile(e);

            if(doRegenerateColors) then begin
                // make sure colors are complete
                FixColors();
            end;

            // now import colors
            if (importDataColors <> nil) then begin
                importColors(importDataColors);
            end;

            // doRegenerateEmblems
            if(doRegenerateEmblems) then begin
                importEmblems(existingContent.O['emblems']);
            end;

            // import emblems
            if(nil <> importDataEmblems) then begin
                importEmblems(importDataEmblems);
            end;

            // doRegenerateBases
            if(doRegenerateBases) then begin
                importBases(existingContent.O['bases']);
            end;

            // import bases
            if(nil <> importDataBases) then begin
                importBases(importDataBases);
            end;

            //doRegenerateArmors
            if(doRegenerateArmors) then begin
                regenArmors();
            end;

        end;

        // remap indices:
        {
            0 => green
            0.0850 => blue
            0.1130 => red
            0.1410 => orange
            0.2300 => lilac
            0.255 => some sort of yellowgreen
            0.3170 => pink
            0.3450 => black
            0.4150 => gray
            0.4510 => white
        }
    end;

    // Called after processing
    // You can remove it if script doesn't require finalization code
    function Finalize: integer;
    begin
        cleanupSS2Lib();
        edidLookupCache.free();
        existingContent.free();

        if(nil <> importDataColors) then begin
            importDataColors.free();
        end;
        if(nil <> importDataEmblems) then begin
            importDataEmblems.free();
        end;
        if(nil <> importDataBases) then begin
            importDataBases.free();
        end;

        Result := 0;
    end;

end.