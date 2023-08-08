{
    Run on anything in targetfile
}
unit GenerateFlags;
    uses 'SS2\SS2Lib'; // uses praUtil

    var
        targetFile, existingElem: IInterface;
        flagName: string;
        editorIdPrefix: string;
        matFile: string;
        matFileBanner: string;
        doRegisterContent: boolean;


    function showConfigGui(): boolean;
    var
        frm: TForm;
        btnOk, btnCancel: TButton;
        nameInput, edidInput, matInput, matInputBanner: TEdit;
        yOffset, resultCode: integer;
        checkRegisterContent: TCheckBox;
    begin
        Result := false;
        frm := CreateDialog('Generate Dynamic Flags', 400, 300);

        yOffset := 10;

        CreateLabel(frm, 10, yOffset, 'Flag Name:');
        nameInput := CreateInput(frm, 10, yOffset+18, flagName);
        nameInput.width := 370;

        yOffset := yOffset + 50;

        CreateLabel(frm, 10, yOffset, 'EditorID prefix:');
        edidInput := CreateInput(frm, 10, yOffset+18, editorIdPrefix);
        edidInput.width := 370;

        yOffset := yOffset + 50;

        CreateLabel(frm, 10, yOffset, 'Path to material file:');
        matInput := CreateInput(frm, 10, yOffset+18, matFile);
        matInput.width := 370;

        yOffset := yOffset + 50;

        CreateLabel(frm, 10, yOffset, '(Optional) Different material file for vertical banners:');
        matInputBanner := CreateInput(frm, 10, yOffset+18, matFileBanner);
        matInputBanner.width := 370;

        //matFileBanner

        yOffset := yOffset + 50;
        checkRegisterContent := CreateCheckbox(frm, 10, yOffset, 'Register content');
        checkRegisterContent.checked := doRegisterContent;
        yOffset := yOffset + 30;

        btnOk     := CreateButton(frm, 100, yOffset, '  OK  ');
        btnCancel := CreateButton(frm, 200, yOffset, 'Cancel');

        btnCancel.ModalResult := mrCancel;

        btnOk.ModalResult := mrYes;
        btnOk.Default := true;


        //nameInput.enabled := false;
        // nameInput.name := 'LevelInput';

        resultCode := frm.showModal();
        if(resultCode = mrYes) then begin
            doRegisterContent := checkRegisterContent.checked;
            flagName := trim(nameInput.text);
            editorIdPrefix := trim(edidInput.text);
            matFile := trim(matInput.text);
            if (flagName <> '') and (editorIdPrefix <> '') and (matFile <> '') then begin
                Result := true;
            end else begin
                AddMessage('Please fill out the fields');
            end;

            matFileBanner := trim(matInputBanner.text);
            if(matFileBanner = '') then begin
                matFileBanner := matFile;
            end;

            globalNewFormPrefix := editorIdPrefix;
        end;

        frm.free();

    end;

    function Initialize: integer;
    begin
        flagName := '';
        editorIdPrefix := '';
        matFile := '';
        matFileBanner := '';
        doRegisterContent := true;
        existingElem := nil;

        Result := 0;
        if(not initSS2Lib()) then begin
            Result := 1;
            exit;
        end;


    end;

    procedure setFirstMswpReplacement(onElem: IInterface; origMat, replaceMat: string);
    var
        newSubs, newSub: IInterface;
    begin
        newSubs := ElementByPath(onElem, 'Material Substitutions');
        newSub := ElementByIndex(newSubs, 0);

        setElementEditValues(newSub, 'BNAM', origMat);
        setElementEditValues(newSub, 'SNAM', replaceMat);
    end;

    function makeFlagMatswap(origMat, replaceMat, prefix, suffix: string): IInterface;
    var
        newEdid: string;
        newSubs, newSub: IInterface;
    begin
        // newEdid := GenerateEdid(flagPrefix, edidBase + '_MWSP_' + suffix);
        //SS2_MS_Banner_USAToGunners
        newEdid := generateEdid('MS_',  prefix + '_' + suffix);
        Result := nil;

        Result := getCopyOfTemplate(targetFile, flagTemplate_Matswap, newEdid);


        setFirstMswpReplacement(Result, origMat, replaceMat);
    end;

    function findPrefix(edid: string): string;
    var
        str: string;
        i: integer;
    begin
        str := edid;
        Result := '';
        for i:=1 to length(str)-1 do begin
            if(str[i] = '_') then begin
                Result := copy(str, 0, i);
                exit;
            end;
        end;
    end;

    function getFirstReplacementMat(mswp: IInterface): string;
    var
        subs, firstSub: IInterface;
    begin
        Result := '';
        subs := ElementByPath(mswp, 'Material Substitutions');
        if(not assigned(subs)) then exit;
        if (ElementCount(subs) = 0) then exit;

        firstSub := ElementByIndex(subs, 0);
        Result := GetElementEditValues(firstSub, 'SNAM');
    end;

    procedure loadExistingData(elem: IInterface);
    var
        theScript, FlagBannerTownStatic, FlagWall: IInterface;
        mswpBanner, mswpWall: IInterface;
    begin
        flagName := GetElementEditValues(elem, 'FULL');
        editorIdPrefix := findPrefix(EditorID(elem));

        theScript := getScript(elem, 'SimSettlementsV2:Armors:ThemeDefinition_Flags');

        FlagBannerTownStatic := getScriptProp(theScript, 'FlagBannerTownStatic');
        FlagWall := getScriptProp(theScript, 'FlagWall');

        mswpBanner := PathLinksTo(FlagBannerTownStatic, 'Model\MODS');
        mswpWall := PathLinksTo(FlagWall, 'Model\MODS');
        //AddMessage();

        matFile := getFirstReplacementMat(mswpWall);
        matFileBanner := getFirstReplacementMat(mswpBanner);
        if(matFileBanner = matFile) then begin
            matFileBanner := '';
        end;

        doRegisterContent := false;

    end;


    function generateFlagsTheme(oldElem: IInterface): IInterface;
    var
        newElem, newScript, newFlagDown, newFlagWaving, newFlagWall: IInterface;
        newFlagBanner, newFlagBannerTorn, newFlagBannerTornWaving, newFlagCircle01, newFlagCircle02: IInterface;
        mswpBanner, mswpCircle, mswpWall, mswpWaving, mswpDown: IInterface;


        themeEdid, nameForEdid: string;

    begin
        Result := nil;

        nameForEdid := cleanStringForEditorID(flagName);
        themeEdid := generateEdid('ThemeDefinition_Flags_', nameForEdid);

        if(assigned(oldElem)) then begin
            newElem := oldElem;
        end else begin
            newElem := getCopyOfTemplate(targetFile, flagTemplate, themeEdid);
        end;
        Result := newElem;

        SetElementEditValues(newElem, 'FULL', flagName);

        newScript := getScript(newElem, 'SimSettlementsV2:Armors:ThemeDefinition_Flags');

        if(assigned(oldElem)) then begin
            newFlagWall := getScriptProp(newScript, 'FlagWall');
            newFlagDown := getScriptProp(newScript, 'FlagDown');
            newFlagWaving := getScriptProp(newScript, 'FlagWaving');

            newFlagBanner := getScriptProp(newScript, 'FlagBannerTownStatic');
            newFlagBannerTorn := getScriptProp(newScript, 'FlagBannerTownTorn');
            newFlagBannerTornWaving := getScriptProp(newScript, 'FlagBannerTownTornWaving');
            newFlagCircle01 := getScriptProp(newScript, 'FlagHalfCircleFlag01');
            newFlagCircle02 := getScriptProp(newScript, 'FlagHalfCircleFlag02');

            mswpDown := PathLinksTo(newFlagDown, 'Model\MODS');
            mswpWaving := PathLinksTo(newFlagWaving, 'Model\MODS');
            mswpWall := PathLinksTo(newFlagWall, 'Model\MODS');
            mswpBanner := PathLinksTo(newFlagBanner, 'Model\MODS');
            mswpCircle := PathLinksTo(newFlagCircle01, 'Model\MODS');

            setFirstMswpReplacement(mswpDown,   'SetDressing\clothflag01alpha.bgsm', matFile);
            setFirstMswpReplacement(mswpWaving, 'SetDressing\Minutemen\FlagMinutemen01Backlit.BGSM', matFile);
            setFirstMswpReplacement(mswpCircle, 'setdressing\HalfCircleFlag01.BGSM', matFile);
            setFirstMswpReplacement(mswpWall,   'SetDressing\Minutemen\FlagMinutemen01.BGSM', matFile);
            setFirstMswpReplacement(mswpBanner, 'SS2\SetDressing\USFlagNoAlphaOneSided.BGSM', matFileBanner);
        end else begin
            // we require 5 matswaps
            {
            SS2_MS_Banner_USAToGunners: SS2\SetDressing\USFlagNoAlphaOneSided.BGSM <- banner, bannerTorn
            SS2_MS_Flag_MMToGunners: SetDressing\Minutemen\FlagMinutemen01.BGSM <- wall flag
            SS2_MS_HalfCircle_USAToGunners: setdressing\HalfCircleFlag01.BGSM <- half circles
            SS2_MS_MinutemenBacklitFlagToGunners: SetDressing\Minutemen\FlagMinutemen01Backlit.BGSM <- waving
            and SS2_MS_USAFlagToGunners: SetDressing\clothflag01alpha.bgsm <- down
            SetDressing\Minutemen\FlagMinutemen01.BGSM
            }

            mswpBanner  := makeFlagMatswap('SS2\SetDressing\USFlagNoAlphaOneSided.BGSM', matFileBanner, 'banner', nameForEdid);
            mswpWall    := makeFlagMatswap('SetDressing\Minutemen\FlagMinutemen01.BGSM', matFile, 'wall', nameForEdid);
            mswpCircle  := makeFlagMatswap('setdressing\HalfCircleFlag01.BGSM', matFile, 'halfcircle', nameForEdid);
            mswpWaving  := makeFlagMatswap('SetDressing\Minutemen\FlagMinutemen01Backlit.BGSM', matFile, 'waving', nameForEdid);
            mswpDown    := makeFlagMatswap('SetDressing\clothflag01alpha.bgsm', matFile, 'down', nameForEdid);

            // now create the actual objects


            {flagTemplate_Wall       := MainRecordByEditorID(staticGroup, 'SS2_FlagWallUSA');
            flagTemplate_Down       := MainRecordByEditorID(staticGroup, 'SS2_FlagDown_USA');
            flagTemplate_Waving     := MainRecordByEditorID(msttGroup, 'SS2_FlagWavingUSA01');}


            newFlagDown   := getCopyOfTemplate(targetFile, flagTemplate_Down, GenerateEdid('FlagDown_', nameForEdid));
            newFlagWaving := getCopyOfTemplate(targetFile, flagTemplate_Waving, GenerateEdid('FlagWaving_', nameForEdid));
            newFlagWall   := getCopyOfTemplate(targetFile, flagTemplate_Wall, GenerateEdid('FlagWall_', nameForEdid));


            newFlagBanner           := getCopyOfTemplate(targetFile, flagTemplate_Banner, GenerateEdid('FlagBanner_', nameForEdid));
            newFlagBannerTorn       := getCopyOfTemplate(targetFile, flagTemplate_BannerTorn, GenerateEdid('FlagBannerTorn_', nameForEdid));
            newFlagBannerTornWaving := getCopyOfTemplate(targetFile, flagTemplate_BannerTornWaving, GenerateEdid('FlagBannerTornWaving_', nameForEdid));

            newFlagCircle01         := getCopyOfTemplate(targetFile, flagTemplate_Circle01, GenerateEdid('FlagHalfCircle01_', nameForEdid));
            newFlagCircle02         := getCopyOfTemplate(targetFile, flagTemplate_Circle02, GenerateEdid('FlagHalfCircle02_', nameForEdid));

             // set props
            setScriptProp(newScript, 'FlagWall', newFlagWall);
            setScriptProp(newScript, 'FlagDown', newFlagDown);
            setScriptProp(newScript, 'FlagWaving', newFlagWaving);

            setScriptProp(newScript, 'FlagBannerTownStatic', newFlagBanner);
            setScriptProp(newScript, 'FlagBannerTownTorn', newFlagBannerTorn);
            setScriptProp(newScript, 'FlagBannerTownTornWaving', newFlagBannerTornWaving);
            setScriptProp(newScript, 'FlagHalfCircleFlag01', newFlagCircle01);
            setScriptProp(newScript, 'FlagHalfCircleFlag02', newFlagCircle02);
        end;

        SetElementEditValues(newFlagDown, 'FULL', flagName);
        SetElementEditValues(newFlagWaving, 'FULL', flagName);
        SetElementEditValues(newFlagWall, 'FULL', flagName);
        SetElementEditValues(newFlagBanner, 'FULL', flagName);
        SetElementEditValues(newFlagBannerTorn, 'FULL', flagName);
        SetElementEditValues(newFlagBannerTornWaving, 'FULL', flagName);
        SetElementEditValues(newFlagCircle01, 'FULL', flagName);
        SetElementEditValues(newFlagCircle02, 'FULL', flagName);



        applyMatswapToModel(mswpDown, -1, newFlagDown);
        applyMatswapToModel(mswpWaving, -1, newFlagWaving);
        applyMatswapToModel(mswpWall, -1, newFlagWall);

        applyMatswapToModel(mswpBanner, -1, newFlagBanner);
        applyMatswapToModel(mswpBanner, -1, newFlagBannerTorn);
        applyMatswapToModel(mswpBanner, -1, newFlagBannerTornWaving);

        applyMatswapToModel(mswpCircle, -1, newFlagCircle01);
        applyMatswapToModel(mswpCircle, -1, newFlagCircle02);

        applyModel(newFlagWall, newElem);

        // registered using SS2_FLID_ThemeDefinitions_Flags [KYWD:0301BB6E]
        if(doRegisterContent) then begin
            registerAddonContent(targetFile, newElem, SS2_FLID_ThemeDefinitions_Flags);
        end;
    end;



    // called for every record selected in xEdit
    function Process(e: IInterface): integer;
    begin
        Result := 0;
        targetFile := GetFile(e);

        if(assigned(getScript(e, 'SimSettlementsV2:Armors:ThemeDefinition_Flags'))) then begin
            existingElem := e;
        end;
        // comment this out if you don't want those messages
        // AddMessage('Processing: ' + FullPath(e));

        // processing code goes here

    end;

    // Called after processing
    // You can remove it if script doesn't require finalization code
    function Finalize: integer;
    var
        flagTheme: IInterface;
    begin
        if(assigned(targetFile)) then begin
            if (assigned(existingElem)) then begin
                AddMessage('yes');
                loadExistingData(existingElem);
            end;

            if(not showConfigGui()) then begin
                Result := 1;
                exit;
            end;

            flagTheme := generateFlagsTheme(existingElem);
        end;
        Result := 0;
        cleanupSS2Lib();
    end;

end.