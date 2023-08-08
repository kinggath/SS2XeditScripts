{
    Script to convert SimSettlements 1 blueprints to the new SimSettlements 2 format
}
unit PlotConverter;

    uses 'SS2\SS2Lib';
    const
        configFile = ProgramPath + 'Edit Scripts\SS2\SS2_PlotConverter.cfg';
        plotMappingFile = ProgramPath + 'Edit Scripts\SS2\PlotMapping.csv';

    var
        newModName: string;
        oldFormPrefix: string;
		newFormPrefix: string;
        autoRegister, makePreviews, setupStacking: boolean;
        lastSelectedFileName: string;
        lastSelectedTargetFileName: string;

        sourceFile: IInterface;
        targetFile: IInterface;

        // addon quest
        currentAddonQuest: IInterface;
        currentAddonMisc: IInterface;

        typeFormlistCache: TJsonObject;


        itemOffsetX, itemOffsetY, itemOffsetZ, levelPlanOffsetX, levelPlanOffsetY, levelPlanOffsetZ: float;

        showDialogForEachPlot: boolean;

        // will be the packed type
        oldPlotType, currentPlotType: integer;

        level4mode: integer;

        signatureBlacklist: TStringList;
        // this will be a cache of converted plots
        formMappingCache: TStringList;
        // skins found in Process() will be put here, then processed in Finalize()
        skinBacklog: TList;

        commercialExteriorQuestProperties: TStringList; // there are so many of them..
        commercialInteriorQuestProperties: TStringList;

        plotMapping: TStringList;



        SS2_FLID_BuildingSkins: IInterface;



    {
        Returns NEW subtype index for an old commercial subtype KW
    }
    function getCommercialSubType(oldKW: IInterface): integer;
    var
        oldEdid: string;
    begin
        oldEdid := EditorID(oldKW);
        Result := PLOT_SC_COM_Default_Other;

        if(oldEdid = 'kgSIM_TypeCommercial_Bar') then begin
            Result := PLOT_SC_COM_Bar;
            exit;
        end;

        if(oldEdid = 'kgSIM_TypeCommercial_ArmorStore') then begin
            Result := PLOT_SC_COM_ArmorStore;
            exit;
        end;

        if(oldEdid = 'kgSIM_TypeCommercial_Beauty') then begin
            Result := PLOT_SC_COM_Beauty;
            exit;
        end;

        if(oldEdid = 'kgSIM_TypeCommercial_Clinic') then begin
            Result := PLOT_SC_COM_Clinic;
            exit;
        end;

        if(oldEdid = 'kgSIM_TypeCommercial_ClothingStore') then begin
            Result := PLOT_SC_COM_ClothingStore;
            exit;
        end;

        if(oldEdid = 'kgSIM_TypeCommercial_FurnitureStore') then begin
            Result := PLOT_SC_COM_FurnitureStore;
            exit;
        end;

        if(oldEdid = 'kgSIM_TypeCommercial_GeneralStore') then begin
            Result := PLOT_SC_COM_GeneralStore;
            exit;
        end;

        if(oldEdid = 'kgSIM_TypeCommercial_Other') then begin
            Result := PLOT_SC_COM_Default_Other;
            exit;
        end;

        if(oldEdid = 'kgSIM_TypeCommercial_PAStore') then begin
            Result := PLOT_SC_COM_PowerArmorStore;
            exit;
        end;

        if(oldEdid = 'kgSIM_TypeCommercial_WeaponStore') then begin
            Result := PLOT_SC_COM_WeaponsStore;
            exit;
        end;
    end;

    {
        Returns NEW subtype index for an old recreational subtype KW
    }
    function getRecreationalSubType(oldKW: IInterface): integer;
    var
        oldEdid: string;
    begin
        oldEdid := EditorID(oldKW);
        Result := PLOT_SC_REC_Default_Relaxation;

        if(oldEdid = 'kgSIM_PlotTypeOverride_Cemetery') then begin
            Result := PLOT_SC_REC_Cemetery;
            exit;
        end;

        if(oldEdid = 'kgSIM_PlotTypeOverride_MessHall') then begin
            Result := PLOT_SC_REC_OutpostType_MessHall;
            exit;
        end;

        if(oldEdid = 'kgSIM_PlotTypeOverride_TrainingYard') then begin
            Result := PLOT_SC_REC_OutpostType_TrainingYard;
            exit;
        end;

    end;


    {
        Returns NEW subtype index for an old martial subtype KW
    }
    function getMartialSubType(oldKW: IInterface): integer;
    var
        oldEdid: string;
    begin
        oldEdid := EditorID(oldKW);
        Result := PLOT_SC_MAR_Default_Basic;

        if(oldEdid = 'kgSIM_PlotTypeOverride_Armory') then begin
            Result := PLOT_SC_MAR_OutpostType_Armory;
            exit;
        end;

        if(oldEdid = 'kgSIM_PlotTypeOverride_BattlefieldScavengers') then begin
            Result := PLOT_SC_MAR_OutpostType_BattlefieldScavengers;
            exit;
        end;

        if(oldEdid = 'kgSIM_PlotTypeOverride_FieldHospital') then begin
            Result := PLOT_SC_MAR_OutpostType_FieldSurgeon;
            exit;
        end;

        if(oldEdid = 'kgSIM_PlotTypeOverride_Prison') then begin
            Result := PLOT_SC_MAR_OutpostType_Prison;
            exit;
        end;

        if(oldEdid = 'kgSIM_PlotTypeOverride_RecruitmentCenter') then begin
            Result := PLOT_SC_MAR_OutpostType_RecruitmentCenter;
            exit;
        end;

        if(oldEdid = 'kgSIM_PlotTypeOverride_WatchTower') then begin
            Result := PLOT_SC_MAR_OutpostType_WatchTower;
            exit;
        end;
    end;

    {
        Returns NEW subtype index for an old plot
    }
    function getSubtypeFromOldPlot(mainType: integer; oldPlot: IInterface): integer;
    var
        oldScript, oldTypeKW: IInterface;
    begin
        oldScript := getScript(oldPlot, 'SimSettlements:SimBuildingPlan');
        // old: PlotTypeOverride in SimSettlements:SimBuildingPlan
        oldTypeKW := getScriptProp(oldScript, 'PlotTypeOverride');

        if(assigned(oldTypeKW)) then begin
            // if old KW exists, map it
            case mainType of
                PLOT_TYPE_COM:
                    begin
                        Result := getCommercialSubType(oldTypeKW);
                        exit;
                    end;
                PLOT_TYPE_REC:
                    begin
                        Result := getRecreationalSubType(oldTypeKW);
                        exit;
                    end;
                PLOT_TYPE_MAR:
                    begin
                        Result := getMartialSubType(oldTypeKW);
                        exit;
                    end;
            end;
        end;

        Result := getDefaultSubtype(mainType);
    end;

    procedure registerConvertedContent(content, kw: IInterface);
    begin
        if(FilesEqual(targetFile, ss2masterFile)) then begin
            // don't do this for SS2 itself
            exit;
        end;

        if(not autoRegister) then begin
            AddMessage('NOTICE: Not registering '+EditorID(content)+', because content registration was disabled');
            exit;
        end;

        AddMessage('Registering '+EditorID(content)+' using '+EditorID(kw));
        registerAddonContent(targetFile, content, kw);
    end;

    {
        Registers a skin with the addon quest
    }
    procedure registerSkin(skin: IInterface; plotType: integer);
    var
        kw: IInterface;
    begin
        kw := getSkinKeywordForPackedPlotType(plotType);
        registerConvertedContent(skin, kw);
    end;

    {
        Registers the plot with the addon quest
    }
    procedure registerPlot(plot: IInterface; plotType: integer);
    var
        kw: IInterface;
    begin
        kw := getPlotKeywordForPackedPlotType(plotType);
        registerConvertedContent(plot, kw);
    end;

    procedure registerPlotWithReqs(plot: IInterface; plotType: integer; reqs: TStringList);
    var
        reqMisc: IInterface;
    begin
        if(FilesEqual(targetFile, ss2masterFile)) then begin
            // don't do this for SS2 itself
            exit;
        end;

        if(not autoRegister) then begin
            AddMessage('NOTICE: Not registering '+EditorID(content)+', because content registration was disabled');
            exit;
        end;

        AddMessage('Registering '+EditorID(plot)+' as unlockable');
        reqMisc := generatePluginReqsMisc(targetFile, reqs);
        registerBuildingPlanWithRequirement(targetFile, plot, reqMisc, '', plotType);
    end;

    procedure addPlotToCache(key: string; newPlot: IInterface);
    var
        i: integer;
    begin
        i := formMappingCache.IndexOf(key);
        if(i < 0) then begin
            formMappingCache.AddObject(key, TObject(newPlot));
            exit;
        end;

        formMappingCache.Objects[i] := TObject(newPlot);
    end;

    function getPlotFromCache(key: string): IInterface;
    var
        i: integer;
    begin
        Result := nil;
        i := formMappingCache.IndexOf(key);
        if(i >= 0) then begin
            Result := ObjectToElement(formMappingCache.Objects[i]);
        end;
    end;

    procedure finalizePlot(oldPlot, newPlot: IInterface; plotType: integer);
    var
        oldScript, oldRequiredPlugins: IInterface;
        i: integer;
        requiredPlugins: TStringList;
        hasReqPlugins: boolean;
        curPluginName: string;
    begin
        // mainType := extractPlotMainType(plotType);
        // subType  := extractPlotSubtype(plotType);
        // size     := extractPlotSize(plotType);

        // subType   := getSubtypeFromOldPlot(mainType, oldPlot);
        // newTypeKW := getSubtypeKeyword(subType);

        // newScript := getScript(newPlot, 'SimSettlementsV2:Weapons:BuildingPlan');

        // stripSubtypeKeywords(newPlot);

        stripTypeKeywords(newPlot);

        // setScriptProp(newScript, 'ClassKeyword', newTypeKW);
        setTypeKeywords(newPlot, plotType);

        // addKeywordByPath(newPlot, newTypeKW, 'KWDA');
        //end;

        setPlotThemes(newPlot, selectedThemeTagList);
        if(selectedThemeTagList <> nil) then begin
            stripThemeKeywords(newPlot);
            for i:=0 to selectedThemeTagList.count-1 do begin
                addKeywordByPath(newPlot, ObjectToElement(selectedThemeTagList.Objects[i]), 'KWDA');
            end;
        end;// otherwise don't touch

        // maybe do not register directly
        hasReqPlugins := false;
        oldScript := getScript(oldPlot, 'SimSettlements:SimBuildingPlan');
        oldRequiredPlugins := getScriptProp(oldScript, 'RequiredPlugins');
        if(assigned(oldRequiredPlugins)) then begin
            requiredPlugins := TSTringList.create;
            for i:=0 to ElementCount(oldRequiredPlugins)-1 do begin
                curPluginName := GetEditValue(ElementByIndex(oldRequiredPlugins, i));
                requiredPlugins.add(curPluginName);
            end;
            if(requiredPlugins.count > 0) then begin
                hasReqPlugins := true;
            end;
        end;

        if(hasReqPlugins) then begin
            registerPlotWithReqs(newPlot, plotType, requiredPlugins);
            requiredPlugins.free();
        end else begin
            registerPlot(newPlot, plotType);
        end;
        addPlotToCache(EditorID(oldPlot), newPlot);
    end;

    {
        Get spawn items offset depending on the plot type
    }
    function getOffsetsByPlotType(plotType: integer): TStringList;
    var
        mainType, size: integer;
    begin
        mainType := extractPlotMainType(plotType);
        size     := extractPlotSize(plotType);

        Result := TStringList.create;

        if(size = SIZE_2x2) then begin
            if
                (mainType = PLOT_TYPE_RES) or
                (mainType = PLOT_TYPE_AGR) or
                (mainType = PLOT_TYPE_IND) or
                (mainType = PLOT_TYPE_MAR) or
                (mainType = PLOT_TYPE_COM)
            then begin
                Result.add('0');
                Result.add('46');
                Result.add('10');
                exit;
            end;
        end;


        // agr3, rec2, mar1 and mar2

        if
            ((mainType = PLOT_TYPE_AGR) and (size = SIZE_3x3)) or
            ((mainType = PLOT_TYPE_REC) and (size = SIZE_2x2)) or
            ((mainType = PLOT_TYPE_MAR) and (size = SIZE_1x1))
        then begin
            Result.add('0');
            Result.add('0');
            Result.add('10');
            exit;
        end;

        Result.add('0');
        Result.add('0');
        Result.add('0');
    end;

    {
        Looks for an Object-type property in the given script, and returns it's name if it points to obj.
    }
    function findPropertyContainingObject(script, obj: IInterface): string;
    var
        propRoot, prop, curFlst: IInterface;
        i: integer;
    begin
        propRoot := ebp(script, 'Properties');
        Result := '';

        if(not assigned(propRoot)) then begin
            exit;
        end;

        for i := 0 to ElementCount(propRoot)-1 do begin
            prop := ElementByIndex(propRoot, i);

            if(geev(prop, 'Type') = 'Object') then begin
                curFlst := LinksTo(ebp(prop, 'Value\Object Union\Object v2\FormID'));
                if(Equals(curFlst, obj)) then begin
                    Result := geev(prop, 'propertyName');
                    exit;
                end;
            end;
        end;
    end;

    function getOldPlotCommercialSubtype(propName: string): integer;
    begin
        Result := -1;
        // Result := packPlotType(PLOT_TYPE_COM, SIZE_INT, -1);
        // Result := packPlotType(PLOT_TYPE_COM, SIZE_2x2, -1);
        // 2x2
        if(propName = 'MyArmorStoreSizeABuildingPlans') then begin
            Result := packPlotType(PLOT_TYPE_COM, SIZE_2x2, PLOT_SC_COM_ArmorStore);
            exit;
        end;
        if(propName = 'MyBarSizeABuildingPlans') then begin
            Result := packPlotType(PLOT_TYPE_COM, SIZE_2x2, PLOT_SC_COM_Bar);
            exit;
        end;
        if(propName = 'MyClinicSizeABuildingPlans') then begin
            Result := packPlotType(PLOT_TYPE_COM, SIZE_2x2, PLOT_SC_COM_Clinic);
            exit;
        end;

        if(propName = 'MyClothingStoreSizeABuildingPlans') then begin
            Result := packPlotType(PLOT_TYPE_COM, SIZE_2x2, PLOT_SC_COM_ClothingStore);
            exit;
        end;
        if(propName = 'MyGeneralStoreSizeABuildingPlans') then begin
            Result := packPlotType(PLOT_TYPE_COM, SIZE_2x2, PLOT_SC_COM_GeneralStore);
            exit;
        end;
        if(propName = 'MyWeaponStoreSizeABuildingPlans') then begin
            Result := packPlotType(PLOT_TYPE_COM, SIZE_2x2, PLOT_SC_COM_WeaponsStore);
            exit;
        end;
        if(propName = 'MyPowerArmorStoreSizeABuildingPlans') then begin
            Result := packPlotType(PLOT_TYPE_COM, SIZE_2x2, PLOT_SC_COM_PowerArmorStore);
            exit;
        end;
        if(propName = 'MyBeautyStoreSizeABuildingPlans') then begin
            Result := packPlotType(PLOT_TYPE_COM, SIZE_2x2, PLOT_SC_COM_Beauty);
            exit;
        end;
        if(propName = 'MyFurnitureStoreSizeABuildingPlans') then begin
            Result := packPlotType(PLOT_TYPE_COM, SIZE_2x2, PLOT_SC_COM_FurnitureStore);
            exit;
        end;
        if(propName = 'MyOtherCommercialSizeABuildingPlans') then begin
            Result := packPlotType(PLOT_TYPE_COM, SIZE_2x2, PLOT_SC_COM_Default_Other);
            exit;
        end;

        // interior
        if(propName = 'MyArmorStoreInteriorBuildingPlans') then begin
            Result := packPlotType(PLOT_TYPE_COM, SIZE_INT, PLOT_SC_COM_ArmorStore);
            exit;
        end;
        if(propName = 'MyBarInteriorBuildingPlans') then begin
            Result := packPlotType(PLOT_TYPE_COM, SIZE_INT, PLOT_SC_COM_Bar);
            exit;
        end;
        if(propName = 'MyClinicInteriorBuildingPlans') then begin
            Result := packPlotType(PLOT_TYPE_COM, SIZE_INT, PLOT_SC_COM_Clinic);
            exit;
        end;
        if(propName = 'MyClothingStoreInteriorBuildingPlans') then begin
            Result := packPlotType(PLOT_TYPE_COM, SIZE_INT, PLOT_SC_COM_ClothingStore);
            exit;
        end;
        if(propName = 'MyGeneralStoreInteriorBuildingPlans') then begin
            Result := packPlotType(PLOT_TYPE_COM, SIZE_INT, PLOT_SC_COM_GeneralStore);
            exit;
        end;
        if(propName = 'MyWeaponStoreInteriorBuildingPlans') then begin
            Result := packPlotType(PLOT_TYPE_COM, SIZE_INT, PLOT_SC_COM_WeaponsStore);
            exit;
        end;
        if(propName = 'MyPowerArmorStoreInteriorBuildingPlans') then begin
            Result := packPlotType(PLOT_TYPE_COM, SIZE_INT, PLOT_SC_COM_PowerArmorStore);
            exit;
        end;
        if(propName = 'MyBeautyStoreInteriorBuildingPlans') then begin
            Result := packPlotType(PLOT_TYPE_COM, SIZE_INT, PLOT_SC_COM_Beauty);
            exit;
        end;
        if(propName = 'MyFurnitureStoreInteriorBuildingPlans') then begin
            Result := packPlotType(PLOT_TYPE_COM, SIZE_INT, PLOT_SC_COM_FurnitureStore);
            exit;
        end;
        if(propName = 'MyOtherCommercialInteriorBuildingPlans') then begin
            Result := packPlotType(PLOT_TYPE_COM, SIZE_INT, PLOT_SC_COM_Default_Other);
            exit;
        end;
    end;

    function getOldMartialSubtype(plotTypeOverride: IInterface): integer;
    var
        curEdid: string;
    begin
        Result := -1;
        if(not assigned(plotTypeOverride)) then exit;

        curEdid := EditorID(plotTypeOverride);
        if(curEdid = 'kgSIM_PlotTypeOverride_Armory') then begin
            Result := PLOT_SC_MAR_OutpostType_Armory;
            exit;
        end;
        if(curEdid = 'kgSIM_PlotTypeOverride_BattlefieldScavengers') then begin
            Result := PLOT_SC_MAR_OutpostType_BattlefieldScavengers;
            exit;
        end;
        if(curEdid = 'kgSIM_PlotTypeOverride_FieldHospital') then begin
            Result := PLOT_SC_MAR_OutpostType_FieldSurgeon;
            exit;
        end;
        if(curEdid = 'kgSIM_PlotTypeOverride_Prison') then begin
            Result := PLOT_SC_MAR_OutpostType_Prison;
            exit;
        end;
        if(curEdid = 'kgSIM_PlotTypeOverride_RecruitmentCenter') then begin
            Result := PLOT_SC_MAR_OutpostType_RecruitmentCenter;
            exit;
        end;
        if(curEdid = 'kgSIM_PlotTypeOverride_WatchTower') then begin
            Result := PLOT_SC_MAR_OutpostType_WatchTower;
            exit;
        end;
    end;

    function getOldRecreationalSubtype(plotTypeOverride: IInterface): integer;
    var
        curEdid: string;
    begin
        Result := -1;
        if(not assigned(plotTypeOverride)) then exit;
        curEdid := EditorID(plotTypeOverride);
        if(curEdid = 'kgSIM_PlotTypeOverride_Cemetery') then begin
            Result := PLOT_SC_REC_Cemetery;
            exit;
        end;
        if(curEdid = 'kgSIM_PlotTypeOverride_MessHall') then begin
            Result := PLOT_SC_REC_OutpostType_MessHall;
            exit;
        end;
        if(curEdid = 'kgSIM_PlotTypeOverride_TrainingYard') then begin
            Result := PLOT_SC_REC_OutpostType_TrainingYard;
            exit;
        end;
    end;

    {
        Tries to figure out an old plot's type, by looking at the quest it's registered with
    }
    function guessPlotType(plot: IInterface): integer;
    var
        i,j, numRefs, numRefsFlst, commResult: integer;
        curFlst, curQust, qustScript, plotTypeOverride, curScript: IInterface;
        propName: string;
    begin
        Result := -1;

        curScript := getScript(plot, 'SimSettlements:SimBuildingPlan');
        plotTypeOverride := getScriptProp(curScript, 'PlotTypeOverride');

        for i:=0 to ReferencedByCount(plot)-1 do begin
            curFlst := ReferencedByIndex(plot, i);
            if(Signature(curFlst) = 'FLST') then begin
                for j:=0 to ReferencedByCount(curFlst)-1 do begin
					curQust := ReferencedByIndex(curFlst, j);
                    if (Signature(curQust) = 'QUST') then begin
                        qustScript := getScript(curQust, 'SimSettlements:AddOnScript');
                        if(assigned(qustScript)) then begin
                            // now find out where exactly curFlst is

                            propName := findPropertyContainingObject(qustScript, curFlst);


                            if(propName = '') then begin
                                exit;
                            end;

                            // commercials with their subtypes
                            // AddMessage('Trying');
                            commResult := getOldPlotCommercialSubtype(propName);
                            // AddMessage('Found this comm type: '+IntToStr(commResult));
                            if(commResult > -1) then begin
                                Result := commResult;
                                exit;
                            end;

                            if(propName = 'MyAgriculturalSizeABuildingPlans') then begin
                                Result := packPlotType(PLOT_TYPE_AGR, SIZE_2x2, -1);
                                exit;
                            end;

                            if(propName = 'MyAgriculturalInteriorBuildingPlans') then begin
                                Result := packPlotType(PLOT_TYPE_AGR, SIZE_INT, -1);
                                exit;
                            end;

                            if(propName = 'MyAgriculturalSize3x3BuildingPlans') then begin
                                Result := packPlotType(PLOT_TYPE_AGR, SIZE_3x3, -1);
                                exit;
                            end;

                            if(propName = 'MyIndustrialSizeABuildingPlans') then begin
                                Result := packPlotType(PLOT_TYPE_IND, SIZE_2x2, -1);
                                exit;
                            end;

                            if(propName = 'MyIndustrialInteriorBuildingPlans') then begin
                                Result := packPlotType(PLOT_TYPE_IND, SIZE_INT, -1);
                                exit;
                            end;

                            if(propName = 'MyAdvancedIndustrialPlans') then begin
                                Result := packPlotType(PLOT_TYPE_IND, SIZE_2x2, -1);
                                exit;
                            end;

                            if(propName = 'MyResidentialSizeABuildingPlans') then begin
                                Result := packPlotType(PLOT_TYPE_RES, SIZE_2x2, -1);
                                exit;
                            end;

                            if(propName = 'MyResidentialInteriorBuildingPlans') then begin
                                Result := packPlotType(PLOT_TYPE_RES, SIZE_INT, -1);
                                exit;
                            end;

                            if(propName = 'MyResidentialInteriorBuildingPlans') then begin
                                Result := packPlotType(PLOT_TYPE_RES, SIZE_INT, -1);
                                exit;
                            end;

                            if(propName = 'MyMartial1x1BuildingPlans') then begin
                                Result := packPlotType(PLOT_TYPE_MAR, SIZE_1x1, getOldMartialSubtype(plotTypeOverride));
                                exit;
                            end;

                            if(propName = 'MyMartial2x2BuildingPlans') then begin
                                Result := packPlotType(PLOT_TYPE_MAR, SIZE_2x2, getOldMartialSubtype(plotTypeOverride));
                                exit;
                            end;

                            if(propName = 'MyMartialInteriorBuildingPlans') then begin
                                Result := packPlotType(PLOT_TYPE_MAR, SIZE_INT, getOldMartialSubtype(plotTypeOverride));
                                exit;
                            end;

                            if(propName = 'MyRecreational2x2BuildingPlans') then begin
                                Result := packPlotType(PLOT_TYPE_REC, SIZE_2x2, getOldRecreationalSubtype(plotTypeOverride));
                                exit;
                            end;

                            if(propName = 'MyRecreationalInteriorBuildingPlans') then begin
                                Result := packPlotType(PLOT_TYPE_REC, SIZE_INT, getOldRecreationalSubtype(plotTypeOverride));
                                exit;
                            end;

                            exit; // in any way, if we found an AddOnScript, exit
                        end;
                    end;
                end;
            end;
        end;
    end;


    procedure applyLevelPlanOffsets(plotType: integer);
    var
        offsetStringList: TStringList;
    begin
        offsetStringList := getOffsetsByPlotType(plotType);


        levelPlanOffsetX := StrToFloat(offsetStringList[0]);
        levelPlanOffsetY := StrToFloat(offsetStringList[1]);
        levelPlanOffsetZ := StrToFloat(offsetStringList[2]);

        offsetStringList.free();
    end;

    {
        Shows a dialog with options for plot conversion
    }
    function showItemOffsetInput(plot: IInterface): boolean;
    begin

        Result := true;
        // kinggath edit: Simplying this since the offsets are always the same
		if(not ShowPlotConversionDialog(plot)) then begin
            Result := false;
            exit;
        end;

		{
		// kinggath edit: We may want to restore this at some point as an option to allow adjusting all of these items, but for now the additional work with rebuilding all of the nif files is excessive. To make it easier, I've added a new field on the BuildingLevelPlan script to allow for offsets applied at run time. It only adds a tiny amount of overhead as the positions of the items have to be relatively calculated to the plot anyway, so we simply do arithmetic before calculating the relative positions.

		offsetStringList := ShowVectorInput('Item Spawn Offset', 'Input offsets for this building plan for'+STRING_LINE_BREAK+infoText+'.', itemOffsetX, itemOffsetY, itemOffsetZ);

		if(offsetStringList <> nil) then begin
            itemOffsetX := StrToFloat(offsetStringList[0]);
            itemOffsetY := StrToFloat(offsetStringList[1]);
            itemOffsetZ := StrToFloat(offsetStringList[2]);
            offsetStringList.free();
        end else begin
            itemOffsetX := 0.0;
            itemOffsetY := 0.0;
            itemOffsetZ := 0.0;
        end;
		}
    end;

	procedure loadPlotMapping();
	var
		csvLines, csvCols: TStringList;
		i: integer;
		curLine, search, replace: string;
		replacePlot, plotScript: IInterface;
	begin
		if(not FileExists(plotMappingFile)) then begin
			exit;
		end;

		plotMapping := TStringList.create;
		plotMapping.CaseSensitive := false;
		plotMapping.Duplicates := dupIgnore;

		AddMessage('Loading plot mapping from '+plotMappingFile);

		csvLines := TStringList.create;
		csvLines.LoadFromFile(plotMappingFile);
		for i:=0 to csvLines.count-1 do begin
			curLine := trim(csvLines.Strings[i]);
			if(curLine = '') then begin
				continue;
			end;

			csvCols := TStringList.create;

			csvCols.Delimiter := ',';
			csvCols.StrictDelimiter := TRUE;
			csvCols.DelimitedText := curLine;

			if (csvCols.count >= 2) then begin
				search  := trim(csvCols.Strings[0]);
				replace := trim(csvCols.Strings[1]);

				if(search <> '') and (replace <>'') then begin
					replacePlot := GetFormByEdid(replace);

					if(assigned(replacePlot)) then begin
						plotScript := getScript(replacePlot, 'SimSettlementsV2:Weapons:BuildingPlan');
						if(assigned(plotScript)) then begin
							plotMapping.addObject(search, replacePlot);
						end else begin
							AddMessage('Cannot use '+search+' => '+replace+' for plot mapping: not a building plan.');
						end;
					end else begin
						AddMessage('Cannot use '+search+' => '+replace+' for plot mapping: building plan not found.');
					end;
				end;
			end;

			csvCols.free();
        end;

		csvLines.free();
	end;


    procedure loadConfig();
    var
        i, j, breakPos: integer;
        curLine, curKey, curVal: string;
        lines : TStringList;
    begin
        // default
        newModName := 'My Addon';
        newFormPrefix := 'addon_';
        oldFormPrefix := '';
        lastSelectedFileName := '';
        showDialogForEachPlot := true;
        level4mode := 0;

        autoRegister := true;
        makePreviews := true;
        setupStacking := true;

		loadPlotMapping();

        if(not FileExists(configFile)) then begin
            exit;
        end;
        lines := TStringList.create;
        lines.LoadFromFile(configFile);



        //
        for i:=0 to lines.count-1 do begin
            curLine := lines[i];
            breakPos := -1;

            for j:=1 to length(curLine) do begin
                if(curLine[j] = '=') then begin
                    breakPos := j;
                    break;
                end;
            end;

            if breakPos <> -1 then begin
                curKey := trim(copy(curLine, 0, breakPos-1));
                curVal := trim(copy(curLine, breakPos+1, length(curLine)));

                if(curKey = 'ModName') then begin
                    newModName := curVal;
                end else if(curKey = 'NewPrefix') then begin
                    newFormPrefix := curVal;
                end else if(curKey = 'OldPrefix') then begin
                    oldFormPrefix := curVal;
                end else if(curKey = 'ShowPlotDialog') then begin
                    showDialogForEachPlot := StrToBool(curVal);
                end else if(curKey = 'LastFile') then begin
                    lastSelectedFileName := curVal;
                end else if(curKey = 'SourceFile') then begin
                    lastSelectedTargetFileName := curVal;
                end else if(curKey = 'AutoRegister') then begin
                    autoRegister := StrToBool(curVal);
                end else if(curKey = 'MakePreviews') then begin
                    makePreviews := StrToBool(curVal);
                end else if(curKey = 'SetupStacking') then begin
                    setupStacking := StrToBool(curVal);
                end else if(curKey = 'L4Mode') then begin
                    level4mode := StrToInt(curVal);
                end;
            end;
        end;

        lines.free();
    end;

    procedure saveConfig();
    var
        lines : TStringList;
    begin
        lines := TStringList.create;
        lines.add('ModName='+newModName);
        lines.add('NewPrefix='+newFormPrefix);
        lines.add('OldPrefix='+oldFormPrefix);
        lines.add('ShowPlotDialog='+BoolToStr(showDialogForEachPlot));
        lines.add('LastFile='+GetFileName(targetFile));
        lines.add('AutoRegister='+BoolToStr(autoRegister));
        lines.add('MakePreviews='+BoolToStr(makePreviews));
        lines.add('SetupStacking='+BoolToStr(setupStacking));
        lines.add('L4Mode='+IntToStr(level4mode));

        if(assigned(sourceFile)) then begin
            lines.add('SourceFile='+GetFileName(sourceFile));
        end;

        lines.saveToFile(configFile);
        lines.free();
    end;

    {
        Shows the main config dialog, where you can select the target file and the prefixes
    }
    function showInitialConfigDialog(): boolean;
    var
        frm: TForm;
        btnOk, btnCancel: TButton;
        inputNewPrefix, inputOldPrefix, inputModName: TEdit;
        resultCode, i, curIndex, selectedIndex: integer;
        selectTargetFile: TComboBox;
        checkShowPlotDialog, checkAutoRegister, checkMakePreviews, checkSetupStacking: TCheckBox;
        s: string;
        yOffset: integer;
    begin
        loadConfig();

        //AddMessage('A '+newModName+', '+newFormPrefix+', '+oldFormPrefix);

        Result := false;
        frm := CreateDialog('Plot Converter', 370, 300);

        CreateLabel(frm, 10, 10, 'Addon Name');
        inputModName := CreateInput(frm, 80, 7, newModName);
        //CreateLabel(frm, 210, 13, '(optional)');


        CreateLabel(frm, 10, 37, 'Target file');
        selectTargetFile := CreateComboBox(frm, 80, 35, 200, nil);
        selectTargetFile.Style := csDropDownList;
        selectTargetFile.Items.Add('-- CREATE NEW FILE --');
        // selectTargetFile.ItemIndex := 0;
        selectedIndex := 0;
        for i := 0 to FileCount - 1 do begin
            s := GetFileName(FileByIndex(i));
            if (Pos(s, readOnlyFiles) > 0) then Continue;

            curIndex := selectTargetFile.Items.Add(s);
            // AddMessage('Fu '+s+', '+lastSelectedFileName);
            if(s = lastSelectedFileName) then begin
                selectedIndex := curIndex;
            end;

        end;
        selectTargetFile.ItemIndex := selectedIndex;


        CreateLabel(frm, 10, 73, 'New prefix');
        inputNewPrefix  := CreateInput(frm, 80, 70, newFormPrefix);
        CreateLabel(frm, 210, 73, '(required)');

        CreateLabel(frm, 10, 93, 'Old prefix');
        inputOldPrefix  := CreateInput(frm, 80, 90, oldFormPrefix);
        CreateLabel(frm, 210, 93, '(optional)');
        CreateLabel(frm, 10, 113, 'The new prefix will be used for newly-generated forms.'+STRING_LINE_BREAK+'If old prefix is given, it will be replace by new prefix.');

        yOffset := 145;

        //yOffset := yOffset + 25;

        checkShowPlotDialog := CreateCheckbox(frm, 10, yOffset, 'Show config dialog for each plot');
        checkShowPlotDialog.checked := showDialogForEachPlot;

        yOffset := yOffset + 25;
// autoRegister, makePreviews
        checkAutoRegister := CreateCheckbox(frm, 10, yOffset, 'Register converted content');
        checkAutoRegister.checked := autoRegister;

        yOffset := yOffset + 25;

        checkMakePreviews := CreateCheckbox(frm, 10, yOffset, 'Generate previews for Building Plans');
        checkMakePreviews.checked := makePreviews;

        yOffset := yOffset + 25;

        checkSetupStacking := CreateCheckbox(frm, 10, yOffset, 'Enable stacked moving for building models');
        checkSetupStacking.checked := setupStacking;

        yOffset := yOffset + 25;



        btnOk := CreateButton(frm, 50, yOffset, 'Start Conversion');
        btnOk.ModalResult := mrYes;
        btnOk.Default := true;

        btnCancel := CreateButton(frm, 250, yOffset, 'Cancel');
        btnCancel.ModalResult := mrCancel;

        resultCode := frm.ShowModal;

        if(resultCode = mrYes) then begin
            newFormPrefix := inputNewPrefix.text;
            oldFormPrefix := inputOldPrefix.text;

            newModName := inputModName.text;
            globalAddonName := newModName;

            showDialogForEachPlot := checkShowPlotDialog.checked;

            if(newFormPrefix = '') then begin
                AddMessage('You must enter a new prefix');
                exit;
            end;

            // maybe create a file
            if (selectTargetFile.ItemIndex = 0) then begin
                // add new here
                targetFile := AddNewFile
            end else begin
                for i := 0 to FileCount - 1 do begin
                    if (selectTargetFile.Text = GetFileName(FileByIndex(i))) then begin
                        targetFile := FileByIndex(i);
                        Break;
                    end;
                    if i = FileCount - 1 then begin
                        AddMessage('The script couldn''t find the file you entered.');
                        targetFile := FileSelect('Select another file');
                    end;
                end;
            end;

            autoRegister := checkAutoRegister.checked;
            makePreviews := checkMakePreviews.checked;

            if(assigned(targetFile)) then begin
                saveConfig();
                Result := true;
            end;
        end;

        frm.free();
    end;

    {
        This should show a dialog for converting a plot
    }
    function ShowPlotTypeDialogForConversion(title, text, extraInfo, okBtnText, cancelBtnText: string; packedType: integer; showL4Dropdown: Boolean): integer;
    var
        frm: TForm;
        btnType1, btnType2, btnThemes: TButton;

        resultCode, selectedMainType, selectedSize, selectedSubType: integer;
        themesLabel: TLabel;
        l4ModeDropdown: TComboBox;
    begin
        isConvertDialogActive := true;
        selectedMainType := -1;
        selectedSize     := -1;
        selectedSubType  := -1;

        if(selectedThemeTagList <> nil) then begin
            selectedThemeTagList.free();
            selectedThemeTagList := nil;
        end;

        Result := -1;
        frm := CreateDialog(title, 450, 225);

        CreateLabel(frm, 10, 6, text);

        CreateLabel(frm, 10, 47, 'Plot Type');

        // plotSubtypeCombobox, plotMainTypeCombobox, plotSizeCombobox
        addPlotTypeDropdowns(frm, 60, 45, packedType);


        CreateLabel(frm, 10, 80, 'Themes');
        btnThemes := CreateButton(frm, 70, 75, 'Select Themes...');
        btnThemes.onclick := themeSelectionClick;


        themesLabel := CreateLabel(frm, 290, 80, 'No themes selected');
        themesLabel.name := 'ThemeIndicatorLabel';


        if(showL4Dropdown) then begin
            // 0 = import all 4
            // 1-4 = which to skip
            CreateLabel(frm, 10, 115, '4-Level processing');

            l4ModeDropdown := CreateComboBox(frm, 120, 112, 100, nil);
            l4ModeDropdown.Style := csDropDownList;

            l4ModeDropdown.Items.add('Import all anyway');
            l4ModeDropdown.Items.add('Skip Level 1');
            l4ModeDropdown.Items.add('Skip Level 2');
            l4ModeDropdown.Items.add('Skip Level 3');
            l4ModeDropdown.Items.add('Skip Level 4');

            l4ModeDropdown.ItemIndex := level4mode;
        end;


        CreateLabel(frm, 10, 140, extraInfo);


        btnType1 := CreateButton(frm, 50, 165, okBtnText);
        btnType1.ModalResult := mrYes;
        btnType1.Default := true;

        plotDialogOkBtn := btnType1;

        btnType2 := CreateButton(frm, 250, 165, cancelBtnText);
        btnType2.ModalResult := mrCancel;


        // selectedThemeTagList


        updatePlotDialogOkBtnState(btnType1);

        resultCode := frm.ShowModal;

        if(resultCode = mrYes) then begin
            selectedMainType := plotMainTypeCombobox.ItemIndex;
            selectedSize     := plotSizeCombobox.ItemIndex;
            selectedSubType  := getSubtypeByIndex(selectedMainType, plotSubtypeCombobox.ItemIndex);

            Result := packPlotType(selectedMainType, selectedSize, selectedSubType);

            if(showL4Dropdown) then begin
                level4mode := l4ModeDropdown.ItemIndex;
            end;
        end;
        frm.free();
    end;

    function getNumLevelForOldPlan(oldPlan: IInterface): integer;
    var
        oldScript, levelStopsArr: IInterface;
    begin
        oldScript := getScript(oldPlan, 'SimSettlements:SimBuildingPlan');

        levelStopsArr := getScriptProp(oldScript, 'LevelStops');

        Result := ElementCount(levelStopsArr);
    end;

    {
        This should show a dialog for converting a plot
    }
    function ShowPlotConversionDialog(plot: IInterface): boolean;
    var
        frm: TForm;
        btnType1, btnType2: TButton;

        resultCode, guessedPlotType, selectedPlotType, numLevels: Integer;

        plotTypeSelect: TComboBox;
        showL4Dropdown: Boolean;
    begin
        // can I guess the type?
        guessedPlotType := guessPlotType(plot);
        oldPlotType := guessedPlotType;
        if(not showDialogForEachPlot) then begin
            // can we get away with not showing it?
            if(guessedPlotType > -1) then begin
                // AddMessage('Guessed Subtype is'+IntToStr(guessedPlotType));
                currentPlotType := ensurePlotSubtype(guessedPlotType);

                AddMessage('Plot "'+EditorID(plot)+'" will be converted as '+getNameForPackedPlotType(currentPlotType));
                Result := true;
                exit;
            end;
        end;

        showL4Dropdown := false;
        // if(oldPlotType
        // oldMainType :=
        numLevels := getNumLevelForOldPlan(plot);
        if(numLevels <= 0) then begin
            AddMessage('=== ERROR: Building Plan '+EditorID(plot)+' has 0 levels! It cannot be converted! ===');
            Result := false;
            exit;
        end;

        if(numLevels > 3) then begin
            showL4Dropdown := true;
        end;

        // showThemeSelectionDialog

        selectedPlotType := ShowPlotTypeDialogForConversion(
            'Converting Plot',
            'Converting plot ' + EditorID(plot) + #13#10 + '"'+DisplayName(plot)+'"',
            'Please make sure the plot type is correct and click ''Convert Plot''.',
            'Convert Plot',
            'Skip Plot',
            guessedPlotType,
            showL4Dropdown
        );

        if(selectedPlotType >= 0) then begin
            currentPlotType := selectedPlotType;
            Result := true;
            if(oldPlotType < 0) then begin
                oldPlotType := currentPlotType;
            end;
        end else begin
            AddMessage('Plot "'+EditorID(plot)+'" will not be converted.');
        end;

    end;


    {
        Translates forms from SimSettlements.esm to SS2
    }
    function translateForm(oldForm: IInterface): IInterface;
    begin
        // maybe do it differently

        Result := translateFormToFile(oldForm, sourceFile, targetFile);
    end;


    {
        Creates a new StageItem form from an old one
    }
    function getNewStageItem(edid, suffix: string; oldSpawnEntry: IInterface; offsetX, offsetY, offsetZ: float): IInterface;
    var
        spawnName, itemEdid: string;
        formToSpawn, oldForm: IInterface;

    begin
        spawnName := getStructMemberDefault(oldSpawnEntry, 'sSpawnName', '');

		oldForm := getFromFromOldSpawnStruct(oldSpawnEntry);
        formToSpawn := translateForm(oldForm);
        // probably here
        addRequiredMastersSilent(formToSpawn, targetFile);

        itemEdid := generateStageItemEdid(
            EditorID(formToSpawn),
            stripPrefix(oldFormPrefix, edid),
            suffix,
            spawnName
        );

        // targetFile: IInterface; edid: string; formToSpawn: IInterface; posX, posY, posZ, rotX, rotY, rotZ, scale: Float; spawnType: integer; vipAV: IInterface; vipVal: integer
        // coords



        Result := createStageItemForm(
            targetFile,
            itemEdid,
            formToSpawn,
            getStructMemberDefault(oldSpawnEntry, 'fOffsetX', 0.0)+offsetX,
            getStructMemberDefault(oldSpawnEntry, 'fOffsetY', 0.0)+offsetY,
            getStructMemberDefault(oldSpawnEntry, 'fOffsetZ', 0.0)+offsetZ,
            getStructMemberDefault(oldSpawnEntry, 'fRotationX', 0.0),
            getStructMemberDefault(oldSpawnEntry, 'fRotationY', 0.0),
            getStructMemberDefault(oldSpawnEntry, 'fRotationZ', 0.0),
            getStructMemberDefault(oldSpawnEntry, 'fScale', 1.0),
            getStructMemberDefault(oldSpawnEntry, 'iType', 0.0),
            '',
            nil
        );
    end;

    function getNewStageItem2(edid, suffix: string; oldSpawnEntry: IInterface; offsetX, offsetY, offsetZ: float): IInterface;
    var
		curFormId: cardinal;
		spawnName, curFileName, itemEdid: string;
        formToSpawn: IInterface;
	begin
		formToSpawn := getStructMember(oldSpawnEntry, 'FormToSpawn');
		if(not assigned(formToSpawn)) then begin

            // try formID/filename
            curFormId := getStructMemberDefault(oldSpawnEntry, 'iExternalFormID', 0);
            curFileName := getStructMemberDefault(oldSpawnEntry, 'sExternalPlugin', '');
            if(curFormId <= 0) or (curFileName = '') then begin
                //Result := getFormByFilenameAndFormID(curFileName, curFormId);
                AddMessage('getNewStageItem failed: found no form to spawn');
                exit;
            end;
		end;

        spawnName := getStructMemberDefault(oldSpawnEntry, 'sSpawnName', '');

        if(assigned(formToSpawn)) then begin
            formToSpawn := translateForm(formToSpawn);

            itemEdid := generateStageItemEdid(
                EditorID(formToSpawn),
                stripPrefix(oldFormPrefix, edid),
                suffix,
                spawnName
            );


            Result := createStageItemForm(
                targetFile,
                itemEdid,
                formToSpawn,
                getStructMemberDefault(oldSpawnEntry, 'fOffsetX', 0.0)+offsetX,
                getStructMemberDefault(oldSpawnEntry, 'fOffsetY', 0.0)+offsetY,
                getStructMemberDefault(oldSpawnEntry, 'fOffsetZ', 0.0)+offsetZ,
                getStructMemberDefault(oldSpawnEntry, 'fRotationX', 0.0),
                getStructMemberDefault(oldSpawnEntry, 'fRotationY', 0.0),
                getStructMemberDefault(oldSpawnEntry, 'fRotationZ', 0.0),
                getStructMemberDefault(oldSpawnEntry, 'fScale', 1.0),
                getStructMemberDefault(oldSpawnEntry, 'iType', 0.0),
                '',
                nil
            );
            exit;
        end;

        itemEdid := generateStageItemEdid(
            curFileName+'_'+IntToHex(curFormId, 8),
            stripPrefix(oldFormPrefix, edid),
            suffix,
            spawnName
        );

        Result := createExternalStageItemForm(
            targetFile,
            itemEdid,
            curFormId,
            curFileName,
            getStructMemberDefault(oldSpawnEntry, 'fOffsetX', 0.0)+offsetX,
            getStructMemberDefault(oldSpawnEntry, 'fOffsetY', 0.0)+offsetY,
            getStructMemberDefault(oldSpawnEntry, 'fOffsetZ', 0.0)+offsetZ,
            getStructMemberDefault(oldSpawnEntry, 'fRotationX', 0.0),
            getStructMemberDefault(oldSpawnEntry, 'fRotationY', 0.0),
            getStructMemberDefault(oldSpawnEntry, 'fRotationZ', 0.0),
            getStructMemberDefault(oldSpawnEntry, 'fScale', 1.0),
            getStructMemberDefault(oldSpawnEntry, 'iType', 0.0),
            '',
            nil
        );
    end;

    function isBuildLimitHelper(oldSpawnEntry: IInterface): boolean;
    var
        edid: string;
    begin
        edid := EditorId(oldSpawnEntry);
        if (strEndsWith(edid, '_BuildLimitHelper')) then begin
            if(GetElementEditValues(oldSpawnEntry, 'Model\MODL') = 'AutoBuildPlots\Helpers\tiny-helper-marker.nif') then begin
                Result := true;
                exit;
            end;
        end;

        Result := false;
    end;

    {
        Convert and old spawn entry to a new one and append it
    }
    procedure convertItemSpawn(oldSpawnEntry, newItemSpawns: IInterface; curLevelStart, curLevelStop, baseBlueprintEdid, suffix: string; spawnStageOffset: integer);
    var
        spawnStageStart, spawnStageEnd: integer;
        adjustedStageStart, adjustedStageEnd: integer;
        newStruct, stageItemDetails, stageItemDetailsStruct: IInterface;

        spawnName : string;

        spawnItem, spawnItemScript: IInterface;
    begin
        // bla
        if(isBuildLimitHelper(oldSpawnEntry)) then begin
            exit;
        end;


        spawnStageStart := getStructMemberDefault(oldSpawnEntry, 'iStageNum', 0);
        spawnStageEnd := getStructMemberDefault(oldSpawnEntry, 'iStageEnd', spawnStageEnd);
        if(spawnStageEnd = 0) then spawnStageEnd := spawnStageStart;

        if(spawnStageStart < curLevelStart) then begin
            spawnStageStart := curLevelStart;
        end;

        if(spawnStageEnd > curLevelStop) then begin
            spawnStageEnd := curLevelStop;
        end;

        if (spawnStageEnd < spawnStageStart) or (spawnStageStart > curLevelStop) or (spawnStageEnd < curLevelStart) then begin
            exit;
        end;

        // create item
        spawnItem := getNewStageItem2(baseBlueprintEdid, suffix, oldSpawnEntry, itemOffsetX, itemOffsetY, itemOffsetZ);
        if(not assigned(spawnItem)) then begin
            // skip
            exit;
        end;


        adjustedStageStart := spawnStageStart - curLevelStart;
        adjustedStageEnd   := spawnStageEnd - curLevelStart;

        newStruct := appendStructToProperty(newItemSpawns);


        setStructMember(newStruct, 'iStageNum', adjustedStageStart+spawnStageOffset);
        if(adjustedStageEnd > adjustedStageStart) then begin
            setStructMember(newStruct, 'iStageEnd', adjustedStageEnd+spawnStageOffset);
        end;

        spawnName := getStructMemberDefault(oldSpawnEntry, 'sSpawnName', '');
        if(spawnName <> '') then begin
            setStructMember(newStruct, 'sLabel', spawnName);
        end;

        // append the item
        setStructMember(newStruct, 'StageItemDetails', spawnItem);
    end;

    procedure migratePlotSettlementResources(oldScript, newScript, buildPlanPathScript: IInterface);
    var
        oldRes, newRes, curOldRes, curNewRes, oldAV, newAV: IInterface;
        i, targetLevel: integer;
        avVal: float;
    begin
        // SettlementResources
        oldRes := getScriptProp(oldScript, 'SettlementResources');
        if(assigned(oldRes)) then begin
            AddMessage('Translating regular plot settlement resources');
            clearScriptProp(newScript, 'SettlementResources');
            newRes := getOrCreateScriptPropArrayOfStruct(newScript, 'SettlementResources');

            for i:=0 to ElementCount(oldRes)-1 do begin
                curOldRes := ElementByIndex(oldRes, i);


                if (assigned(curOldRes)) then begin
                    oldAV := getStructMember(curOldRes, 'AVToChange');
                    avVal := getStructMemberDefault(curOldRes, 'AVValue', 0.0);
                    targetLevel := getStructMemberDefault(curOldRes, 'iLevel', 0);

                    if (targetLevel = 0) or (avVal = 0) or (not assigned(oldAV)) then begin
                        AddMessage('Invalid settlement resource:');
                        dumpElem(curOldRes);
                    end else begin
                        newAV := translateForm(oldAv);
                        if(assigned(newAV)) then begin
                            curNewRes := appendStructToProperty(newRes);

                            setStructMember(curNewRes, 'fAmount', avVal);
                            setStructMember(curNewRes, 'iLevel', targetLevel);
                            setStructMember(curNewRes, 'ResourceAV', newAV);
                        end;
                    end;
                end;
            end;

            exit;
        end;

    end;

    procedure migratePlotProduction(oldScript, newScript, buildPlanPathScript: IInterface);
    var
        oldResourcesGenerated, curOldResource, newResourcesGenerated, curNewResource, newResStruct: IInterface;
        curSubPlanLevel, i: integer;
    begin
        oldResourcesGenerated := getScriptProp(oldScript, 'ResourcesGenerated');

        // resources production
        if(assigned(oldResourcesGenerated)) then begin
            AddMessage('Translating regular plot production');
            clearScriptProp(newScript, 'ProducedItems');
            newResourcesGenerated := getOrCreateScriptPropArrayOfStruct(newScript, 'ProducedItems');

            for i:=0 to ElementCount(oldResourcesGenerated) do begin // i is levelNr, starting at 0
                // in this case index is level
                curOldResource := getObjectFromProperty(oldResourcesGenerated, i);

                // dumpElem(curOldResource);
                if(assigned(curOldResource)) then begin
                    curNewResource := translateForm(curOldResource);
                    if(assigned(curNewResource)) then begin
                        // put in
                        newResStruct := appendStructToProperty(newResourcesGenerated);

                        // fill out
                        setStructMember(newResStruct, 'Item', curNewResource);
                        setStructMember(newResStruct, 'iLevel', i+1);
                    end;
                end;
            end;

            exit;
        end;

        // otherwise, try the other stuff

        {
        curSubPlanScript := getScript(curSubPlan, 'SimSettlements:SimPlanPath');

        // the children of curSubPlan will need this
        //BaseUpgradeMaterials := getScriptProp(curSubPlanScript, 'BaseUpgradeMaterials');// array of struct
        CreateResources := translateForm(getScriptProp(curSubPlanScript, 'CreateResources')); // just one object, an LVLI
        }
        if(assigned(buildPlanPathScript)) then begin
            curOldResource := getScriptProp(buildPlanPathScript, 'CreateResources'); // just one object, an LVLI

            if(assigned(curOldResource)) then begin

                curNewResource := translateForm(curOldResource);

                if(assigned(curNewResource)) then begin
                    AddMessage('Translating path-based plot production');
                    clearScriptProp(newScript, 'ProducedItems');
                    newResourcesGenerated := getOrCreateScriptPropArrayOfStruct(newScript, 'ProducedItems');
                    // old level, 0-2
                    curSubPlanLevel := getScriptPropDefault(buildPlanPathScript, 'Requirement_Level', 0);

                    newResStruct := appendStructToProperty(newResourcesGenerated);

                    setStructMember(newResStruct, 'Item', curNewResource);
                    setStructMember(newResStruct, 'iLevel', curSubPlanLevel+1);
                end;
            end;
        end;

    end;

    procedure addToStackEnabledListIfEnabled(model: IInterface);
    begin
        if(not setupStacking) then exit;

        addToStackEnabledList(targetFile, model);
    end;

    procedure convertStages(oldBlueprint: IInterface; newBlueprint: IInterface; planEdidBase: string);
    var
        levelStopsArr, stagesArr, itemSpawnsArr : IInterface;
        numStages, numLevels: integer;
        oldScript, newScript: IInterface;

        curTargetLevelNr, curLevelNr, curStageNr, curLevelStart, curLevelStop, prevLevelStop, spawnStageOffset: integer;
        lastLevel, currentLevel: integer;

        curLevelBlueprint, curLevelBlueprintScript, levelPlanOffsets, propValue, newEntry: IInterface;
        newStageModels, newItemSpawns: IInterface;

        levelFormlist, curStageModel: IInterface;

        itemSpawnIndex, lastItemSpawnIndex, spawnStageNum, spawnStageEnd, i: integer;
        currentItemSpawn, formToSpawn: IInterface;

        itemSpawnEdidBase, spawnName: string;

        offsetStringList: TStringList;

        itemSpawnsByLevel: TJsonObject;
        curSpawnArr: TJsonArray; // mapping: level nr -> array of relevant indices from itemSpawnsArr

        playerSelectOnly: Boolean;

    begin
        oldScript := getScript(oldBlueprint, 'SimSettlements:SimBuildingPlan');
        newScript := getScript(newBlueprint, 'SimSettlementsV2:Weapons:BuildingPlan');



        levelStopsArr := getScriptProp(oldScript, 'LevelStops');
        numLevels := ElementCount(levelStopsArr);

        if(numLevels <= 0) then begin
            AddMessage('=== ERROR: Building Plan '+EditorID(oldBlueprint)+' has 0 levels! It cannot be converted! ===');
            exit;
        end;

        if(numLevels > 4) then begin
            numLevels := 4;
        end;


        stagesArr := getScriptProp(oldScript, 'StageModels');
        numStages := ElementCount(stagesArr);

        itemSpawnsArr := getScriptProp(oldScript, 'StageItemSpawns');

        levelFormlist := getScriptProp(newScript, 'LevelPlansList');
        clearFormList(levelFormlist);

        migratePlotProduction(oldScript, newScript, nil);
        migratePlotSettlementResources(oldScript, newScript, nil);

        // preprocess the spawns
        itemSpawnsByLevel := TJsonObject.create;

        playerSelectOnly := getScriptPropDefault(oldScript, 'bDirectSelectOnly', true);
        if(playerSelectOnly) then begin
            setScriptProp(newScript, 'bPlayerSelectOnly', playerSelectOnly);
        end else begin
            deleteScriptProp(newScript, 'bPlayerSelectOnly');
        end;


//level4mode
        for itemSpawnIndex:=0 to ElementCount(itemSpawnsArr)-1 do begin
            {
                level stops:
                0 => 2, 1 => 4, 2 => 6
            }

            // check for which levels this is applicable
            currentItemSpawn :=  ElementByIndex(itemSpawnsArr, itemSpawnIndex);

            spawnStageNum := getStructMemberDefault(currentItemSpawn, 'iStageNum', 0);
            spawnStageEnd := getStructMemberDefault(currentItemSpawn, 'iStageEnd', -1);

            // find the level where this begins
            prevLevelStop := 0;
            for curLevelNr :=0 to numLevels-1 do begin
                curLevelStop := StrToInt(GetEditValue(ElementByIndex(levelStopsArr, curLevelNr)));


                curSpawnArr := itemSpawnsByLevel.A[curLevelNr];

                if(spawnStageEnd = -1) then begin
                    if(spawnStageNum > prevLevelStop) and (spawnStageNum <= curLevelStop) then begin
                        curSpawnArr.add(itemSpawnIndex);
                    end;
                end else begin
                    // spawnStageNum -> spawnStageEnd must intersect prevLevelStop -> curLevelStop
                    // - spawnStageNum can't be > curLevelStop
                    // - spawnStageNum can be < curLevelStop
                    // - spawnStageNum can be < prevLevelStop

                    // - spawnStageEnd must be > prevLevelStop
                    // - spawnStageEnd must be > curLevelStop
                    if (spawnStageNum <= curLevelStop) and (spawnStageEnd > prevLevelStop) then begin
                        curSpawnArr.add(itemSpawnIndex);
                    end;
                end;


                prevLevelStop := curLevelStop;
            end;
        end;

        // AddMessage('Got this for itemSpawnsByLevel:');
        // AddMessage(itemSpawnsByLevel.toString());

        curLevelStart := 0;
        curLevelStop := 0;
        lastItemSpawnIndex := 0;
        curTargetLevelNr := 0;

        for curLevelNr:=0 to numLevels-1 do begin
            if(curLevelNr>0) then begin
                curLevelStart := curLevelStop+1;
            end;

            // check skipping
            if(numLevels = 4) then begin
                // level4mode
                if(level4mode > 0) then begin
                    if (level4mode = (curLevelNr+1)) then begin
                        // skip this level
                        AddMessage('Skipping level '+IntToStr(curLevelNr+1));
                        continue;
                    end;
                end;
            end;

            curTargetLevelNr := curTargetLevelNr+1;

            AddMessage('Processing level '+IntToStr(curLevelNr+1)+'...');

            curLevelStop := StrToInt(GetEditValue(ElementByIndex(levelStopsArr, curLevelNr)));
            curLevelBlueprint := getOrCreateBuildingPlanForLevel(targetFile, newBlueprint, planEdidBase, curTargetLevelNr);
            // set the level plan name
            SetEditValueByPath(curLevelBlueprint, 'FULL', geev(newBlueprint, 'FULL')+' Level '+IntToStr(curTargetLevelNr));
            // append it to the formlist
            addToFormlist(levelFormlist, curLevelBlueprint);

            curLevelBlueprintScript := getScript(curLevelBlueprint, 'SimSettlementsV2:Weapons:BuildingLevelPlan');
            setScriptProp(curLevelBlueprintScript, 'iRequiredLevel', curTargetLevelNr);

            setScriptProp(curLevelBlueprintScript, 'ParentBuildingPlan', newBlueprint);


            // uniforms
            migrateUniforms(oldScript, curLevelBlueprintScript);

            clearScriptProperty(curLevelBlueprintScript, 'PositionOffsets');
            // Check for offsets
            // AddMessage('checking for offsets '+FloatToStr(levelPlanOffsetX)+', '+FloatToStr(levelPlanOffsetY)+', '+FloatToStr(levelPlanOffsetZ));

            writeOffsetsArray(curLevelBlueprintScript, 'PositionOffsets');

            // do stage models
            newStageModels := createRawScriptProp(curLevelBlueprintScript, 'StageModels');
            SetEditValueByPath(newStageModels, 'Type', 'Array of Object');

            clearProperty(newStageModels);
            for curStageNr:=curLevelStart to curLevelStop do begin

                curStageModel := LinksTo(ElementByPath(ElementByIndex(stagesArr, curStageNr), 'Object v2\FormID'));

                curStageModel := translateForm(curStageModel);

                addToStackEnabledListIfEnabled(curStageModel);

                // hack for BuildingMaterialsOverride
                if (curTargetLevelNr = 1) and (curStageNr = 0) then begin
                    // use the very first one as BuildingMaterialsOverride
                    setScriptProp(newScript, 'BuildingMaterialsOverride', curStageModel);
                    // here, offsets might be relevant again

                    if (FilesEqual(GetFile(curStageModel), targetFile)) then begin
                        // apply them to newScript
                        writeOffsetsArray(newScript, 'BuildingMaterialsOverridePositionOffsets');
                    end;
                end else begin
                    appendObjectToProperty(newStageModels, curStageModel);
                end;

                if(makePreviews) then begin
                    // assign models. these are the previews
                    if(curStageNr = curLevelStop) then begin
                        if(Signature(curStageModel) <> 'SCOL') then begin
                            applyModel(curStageModel, curLevelBlueprint);
                            if(curTargetLevelNr = 1) then begin
                                applyModel(curStageModel, newBlueprint);
                            end;
                        end;
                    end;
                end;
            end;

            newItemSpawns := createRawScriptProp(curLevelBlueprintScript, 'StageItemSpawns');
            SetEditValueByPath(newItemSpawns, 'Type', 'Array of Struct');
            cleanItemSpawns(newItemSpawns);

            // NOW DO ITEM SPAWNS
            curSpawnArr := itemSpawnsByLevel.A[curLevelNr];
            if(curSpawnArr.count > 0) then begin
            // end;

            // if (ElementCount(itemSpawnsArr) > 0) then begin
                spawnStageOffset := IfThen(curLevelNr = 0, 0, 1);

                for i:=0 to curSpawnArr.count-1 do begin

                    itemSpawnIndex := curSpawnArr.I[i];
                // for itemSpawnIndex := lastItemSpawnIndex to ElementCount(itemSpawnsArr)-1 do begin
                    currentItemSpawn :=  ElementByIndex(itemSpawnsArr, itemSpawnIndex);


                    spawnStageNum := getStructMemberDefault(currentItemSpawn, 'iStageNum', 0);
                    spawnStageEnd := getStructMemberDefault(currentItemSpawn, 'iStageEnd', spawnStageEnd);
                    spawnName     := getStructMemberDefault(currentItemSpawn, 'sSpawnName', '');

                    // formToSpawn   := translateForm(getStructMember(currentItemSpawn, 'FormToSpawn'));

                    //itemSpawnEdidBase := generateEdid(stageItemPrefix, StripPrefix(levelPlanPrefix, EditorID(curLevelBlueprint))+'_'+getStructMemberDefault(currentItemSpawn, 'sSpawnName', 'spawn')+'_'+IntToStr(itemSpawnIndex));

                    // something like
                    // LevelPlan_praSim_BuildingPlan_cArFrame_lvl3
                    itemSpawnEdidBase := planEdidBase+'_lvl'+IntToStr(curTargetLevelNr);

                    convertItemSpawn(
                        currentItemSpawn,
                        newItemSpawns,
                        curLevelStart,
                        curLevelStop,
                        itemSpawnEdidBase,
                        IntToStr(itemSpawnIndex),
                        spawnStageOffset{,
                        formToSpawn}
                    );

                    if (spawnStageNum > curLevelStop) then begin
                        //AddMessage('Skipping the rest');
                        // continue from here next iteration
                        lastItemSpawnIndex := itemSpawnIndex;
                        break;
                    end;
                end;

                // backlog
            end;
        end;

        itemSpawnsByLevel.free();
    end;

    procedure migrateUniforms(oldPlotScript, newPlotScript: IInterface);
    var
        oldUniformProp: IInterface;
        newUniformProp: IInterface;
        i: integer;
        oldOutfit, newOutfit: IInterface;
    begin
        // ExtraPlaqueInfo
        oldUniformProp := getScriptProp(oldPlotScript, 'UniformOutfits');
        if(not assigned(oldUniformProp)) then exit;

        newUniformProp := getOrCreateScriptPropArrayOfObject(newPlotScript, 'AutoEquip');
        clearProperty(newUniformProp);

        for i:=0 to ElementCount(oldUniformProp)-1 do begin
            //DumpElem(ElementByIndex(oldUniformProp, i));
            //oldOutfit := LinksTo(ElementByIndex(oldUniformProp, i));
            oldOutfit := getObjectFromProperty(oldUniformProp, i);
            newOutfit := translateForm(oldOutfit);

            if(assigned(newOutfit)) then begin
                appendObjectToProperty(newUniformProp, newOutfit);
            end;
        end;
    end;

    {
        Write the values in levelPlanOffsetX/Y/Z into an array of float script property of the given name
    }
    procedure writeOffsetsArray(targetScript: IInterface; propName: string);
    var
        levelPlanOffsets, propValue, newEntry: IInterface;
    begin
        if(levelPlanOffsetX <> 0.0 or levelPlanOffsetY <> 0.0 or levelPlanOffsetZ <> 0.0) then begin
            clearScriptProp(targetScript, propName);

            levelPlanOffsets := createRawScriptProp(targetScript, propName);
            SetEditValueByPath(levelPlanOffsets, 'Type', 'Array of Float');

            propValue := ebp(levelPlanOffsets, 'Value\Array of Float');
            newEntry := ElementAssign(propValue, HighInteger, nil, false);
            SetEditValue(newEntry, levelPlanOffsetX);
            newEntry := ElementAssign(propValue, HighInteger, nil, false);
            SetEditValue(newEntry, levelPlanOffsetY);
            newEntry := ElementAssign(propValue, HighInteger, nil, false);
            SetEditValue(newEntry, levelPlanOffsetZ);
            // dumpElem(propValue);
        end;
    end;

    procedure processBranchingLevel(curLevel: integer; blueprintRoot, BuildingPlans, curSubPlanScript: IInterface; planEdidBase: string);
    var
        i, j, spawnStageNum, spawnStageEnd, numStages: integer;
        blueprintRootScript,levelBlueprints, curOldBlueprint, curOldBlueprintScript, newItemSpawns: IInterface;
        ExtraPlaqueInfo, oldStageModels, levelPlanOffsets, propValue, newEntry, newStageModels, curStageModel, ExtraProduction: IInterface;
        curLevelBlueprint, curLevelBlueprintScript, itemSpawnsArr, currentItemSpawn, curResourceItem, formToSpawn: IInterface;
        levelBlueprintEdid, itemSpawnEdidBase, spawnName, levelEdidBase: string;
    begin
        blueprintRootScript := getScript(blueprintRoot, 'SimSettlementsV2:Weapons:BuildingPlan');
        levelBlueprints := getScriptProp(blueprintRootScript, 'LevelPlansList');

        // migrate uniforms here
            migrateUniforms(blueprintRootScript, getScript(blueprintRoot, 'SimSettlementsV2:Weapons:BuildingPlan'));

        for i:=0 to getFormListLength(BuildingPlans)-1 do begin
            // each iteration here should produce a BuildingLevelPlan, each of them should have the given level
            curOldBlueprint := getFormListEntry(BuildingPlans, i);
            // this is a SimSettlements:SimBuildingPlan
            curOldBlueprintScript := getScript(curOldBlueprint,'SimSettlements:SimBuildingPlan');

            levelEdidBase := stripPrefix(buildingPlanPrefix, stripPrefix(oldFormPrefix, EditorID(curOldBlueprint)));

            levelBlueprintEdid := GenerateEdid(levelPlanPrefix, levelEdidBase);

 		    AddMessage('Processing '+getElementEditValues(curOldBlueprint, 'FULL')+' as Level '+IntToStr(curLevel+1)+' Variant '+IntToStr(i+1));


            //getOrCreateBuildingPlanForLevel(targetFile, newBlueprint, planEdidBase, curLevelNr+1);
            //curLevelBlueprint := getOrCreateBuildingPlanForLevel(targetFile, levelBlueprintEdid, planEdidBase, curLevel);
            curLevelBlueprint := getBuildingPlanForLevel(targetFile, levelBlueprintEdid, curLevel);

            curLevelBlueprintScript := getScript(curLevelBlueprint, 'SimSettlementsV2:Weapons:BuildingLevelPlan');

            SetEditValueByPath(curLevelBlueprint, 'FULL', getElementEditValues(curOldBlueprint, 'FULL'));

            addToFormList(levelBlueprints, curLevelBlueprint);

            setScriptProp(curLevelBlueprintScript, 'ParentBuildingPlan', blueprintRoot);
            setScriptProp(curLevelBlueprintScript, 'iRequiredLevel', curLevel+1);

            ExtraPlaqueInfo := getScriptProp(curOldBlueprintScript, 'ExtraPlaqueInfo');

            if(assigned(ExtraPlaqueInfo)) then begin
                setBlueprintDescription(curLevelBlueprint, getElementEditValues(ExtraPlaqueInfo, 'DESC'), targetFile);
                setBlueprintConfirmation(curLevelBlueprint, getElementEditValues(ExtraPlaqueInfo, 'DESC'), targetFile);
                if (curLevel = 0) and (i = 0) then begin
                    setBlueprintDescription(blueprintRoot, getElementEditValues(ExtraPlaqueInfo, 'DESC'), targetFile);
                    setBlueprintConfirmation(blueprintRoot, getElementEditValues(ExtraPlaqueInfo, 'DESC'), targetFile);
                end;
            end;

            // Check for offsets
            writeOffsetsArray(curLevelBlueprintScript, 'PositionOffsets');

            migratePlotProduction(curOldBlueprintScript, curLevelBlueprintScript, curSubPlanScript);
            migratePlotSettlementResources(curOldBlueprintScript, curLevelBlueprintScript, curSubPlanScript);



            // do stage models
            newStageModels := createRawScriptProp(curLevelBlueprintScript, 'StageModels');
            SetEditValueByPath(newStageModels, 'Type', 'Array of Object');
            clearProperty(newStageModels);
            oldStageModels := getScriptProp(curOldBlueprintScript, 'StageModels');
            numStages := ElementCount(oldStageModels);
            for j:= 0 to numStages-1 do begin
                // applyModel
                curStageModel := pathLinksTo(ElementByIndex(oldStageModels, j), 'Object v2\FormID');//LinksTo(ebp(ElementByIndex(oldStageModels, j), 'Object v2\FormID'));
                curStageModel := translateForm(curStageModel);

                addToStackEnabledListIfEnabled(curStageModel);

                appendObjectToProperty(newStageModels, curStageModel);

                if(makePreviews) then begin
                    // assign models
                    if (j = numStages-1) then begin
                        if(Signature(curStageModel) <> 'SCOL') then begin
                            // apply it to the level blueprint
                            applyModel(curStageModel, curLevelBlueprint);
                            if (i = 0) and (curLevel = 0) then begin
                                // apply it to the root, too
                                applyModel(curStageModel, blueprintRoot);
                            end;
                        end;
                    end;
                end;
            end; // oldStageModels loop

            // item spawns
            // here, too
            itemSpawnsArr := getScriptProp(curOldBlueprintScript, 'StageItemSpawns');

            if (ElementCount(itemSpawnsArr) > 0) then begin
                newItemSpawns := createRawScriptProp(curLevelBlueprintScript, 'StageItemSpawns');
                SetEditValueByPath(newItemSpawns, 'Type', 'Array of Struct');
                cleanItemSpawns(newItemSpawns);

                for j := 0 to ElementCount(itemSpawnsArr)-1 do begin
                    currentItemSpawn :=  ElementByIndex(itemSpawnsArr, j);

                    spawnStageNum := getStructMemberDefault(currentItemSpawn, 'iStageNum', 0);
                    spawnStageEnd := getStructMemberDefault(currentItemSpawn, 'iStageEnd', spawnStageEnd);

                    spawnName     := getStructMemberDefault(currentItemSpawn, 'sSpawnName', '');

                    // formToSpawn   := translateForm(getStructMember(currentItemSpawn, 'FormToSpawn'));

                    itemSpawnEdidBase := generateEdid(stageItemPrefix, levelEdidBase);

                    convertItemSpawn(
                        currentItemSpawn,
                        newItemSpawns,
                        0,
                        numStages,
                        itemSpawnEdidBase,//StripPrefix(newFormPrefix, StripPrefix(levelPlanPrefix, EditorID(curLevelBlueprint))),//itemSpawnEdidBase,
                        IntToStr(j),
                        1{,
                        formToSpawn}
                    );
                    //StripPrefix(newFormPrefix, StripPrefix(levelPlanPrefix, EditorID(curLevelBlueprint)))
                end;
            end;

            {
            if(assigned(CreateResources)) then begin // this is from the path
                // apply resources
                ExtraProduction := createRawScriptProp(curLevelBlueprintScript, 'ExtraProduction');
                SetEditValueByPath(ExtraProduction, 'Type', 'Array of Struct');
                clearProperty(ExtraProduction);

                curResourceItem := appendStructToProperty(ExtraProduction);
                setStructMember(curResourceItem, 'ResourceAV', CreateResources);
                setStructMember(curResourceItem, 'fAmount', 1.0);
            end else begin
                deleteScriptProp(curLevelBlueprintScript, 'ExtraProduction');
            end;
            }
        end; // BuildingPlans loop

    end;

    function isPartOfBranchingBlueprint(plot: IInterface): boolean;
    var
        i,j: integer;
        curFlst, curMisc, curMiscScript, probablyFlst: IInterface;
    begin
        Result := false;

        for i:=0 to ReferencedByCount(plot)-1 do begin

            curFlst := ReferencedByIndex(plot, i);
            if(signature(curFlst) = 'FLST') then begin

                for j:=0 to ReferencedByCount(curFlst)-1 do begin
                    curMisc := ReferencedByIndex(curFlst, j);
                    if(signature(curMisc) = 'MISC') then begin
                        curMiscScript := getScript(curMisc, 'SimSettlements:SimPlanPath');
                        if(assigned(curMiscScript)) then begin
                            // does it have a BuildingPlans?
                            probablyFlst := getScriptProp(curMiscScript, 'BuildingPlans');
                            if (assigned(probablyFlst) and equals(probablyFlst, curFlst)) then begin
                                Result := true;
                                exit;
                            end;
                        end;
                    end;
                end;
            end;
        end;
    end;

    procedure processBranchingBuildingPlan(e: IInterface; script: IInterface; buildPlanPaths: IInterface);
    var
        i, curSubPlanLevel: integer;
		bpEdId, oldName, planEdidBase: string;
        curSubPlan, newRoot, formList, curSubPlanScript: IInterface;
        BaseUpgradeMaterials, CreateResources, WorkshopAVsToSet, BuildingPlans: IInterface;
    begin
        AddMessage('Converting BRANCHING blueprint '+geev(e, 'FULL'));
        //extraInfo := getScriptProp(script, 'ExtraPlaqueInfo');

        planEdidBase := StripPrefix(masterBuildingPlanPrefix, StripPrefix(buildingPlanPrefix, StripPrefix(oldFormPrefix, EditorID(e))));

        bpEdId := GenerateEdid(buildingPlanPrefix, planEdidBase);

        // e doesn't have much information on it, besides the FULL

        oldName := geev(e, 'FULL - Name');
        newRoot := prepareBlueprintRoot(targetFile, nil, bpEdId, oldName, oldName + ' Description', oldName + ' Confirmation');



        for i:=0 to getFormListLength(buildPlanPaths)-1 do begin
            curSubPlan := getFormListEntry(buildPlanPaths, i);
            // this has SimSettlements:SimPlanPath
            curSubPlanScript := getScript(curSubPlan, 'SimSettlements:SimPlanPath');

            // the children of curSubPlan will need this
            //BaseUpgradeMaterials := getScriptProp(curSubPlanScript, 'BaseUpgradeMaterials');// array of struct
            // CreateResources := translateForm(getScriptProp(curSubPlanScript, 'CreateResources')); // just one object, an LVLI
            //WorkshopAVsToSet := getScriptProp(curSubPlanScript, 'WorkshopAVsToSet'); // array of object

            BuildingPlans := getScriptProp(curSubPlanScript, 'BuildingPlans'); // FLST, contains the actual blueprint

            // LevelKeyword should be important somehow
            // this seems to be the level, 0-2
            curSubPlanLevel := getScriptPropDefault(curSubPlanScript, 'Requirement_Level', 0);

            processBranchingLevel(curSubPlanLevel, newRoot, BuildingPlans, curSubPlanScript, planEdidBase);
        end;

        // register it
        finalizePlot(e, newRoot, currentPlotType);

        AddMessage('Converting finished.');
    end;

    procedure updateSkinTargetOkBtn(sender: TObject);
    var
        targetForm: TForm;
        inputEdid: TEdit;
    begin
        if(plotDialogOkBtn = nil) then exit;

        targetForm := TForm(sender.parent);
        inputEdid   := TEdit(targetForm.FindComponent('InputPlotEdid'));

        plotDialogOkBtn.enabled := (inputEdid.text <> '');
    end;

    function selectSkinTargePlot(oldSkin, oldTarget: IInterface): IInterface;
    var
        frm: TForm;
        resultCode: integer;
        btnOk, btnCancel, btnBrowse: TButton;
        potentialTarget, targetScript: IInterface;
        selectedEdid: string;
    begin
        Result := nil;
        frm := CreateDialog('Select Skin Target', 600, 200);
        CreateLabel(frm, 10, 5, 'Select target for skin '+EditorID(oldSkin)+' "'+GetElementEditValues(oldSkin, 'FULL')+'"');
        if(assigned(oldTarget)) then begin
            CreateLabel(frm, 10, 25, 'Old target was: '+EditorID(oldTarget)+' "'+GetElementEditValues(oldTarget, 'FULL')+'"');
        end;

        CreateLabel(frm, 10, 67, 'Target Building Plan (Editor ID):');

        plotEdidInput := CreateInput(frm, 10, 85, '');
        plotEdidInput.Name := 'InputPlotEdid';
        plotEdidInput.Text := '';
        plotEdidInput.onChange := updateSkinTargetOkBtn;
        plotEdidInput.width := 530;

        btnBrowse := CreateButton(frm, 550, 83, '...');
        btnBrowse.OnClick := browseTargetPlot;


        btnOk := CreateButton(frm, 100, 130, '  OK  ');
        btnOk.ModalResult := mrYes;
        btnOk.Enabled := false;
        btnOk.Default := true;
        plotDialogOkBtn := btnOk;

        btnCancel := CreateButton(frm, 400, 130, ' Cancel ');
        btnCancel.ModalResult := mrCancel;

        resultCode := frm.ShowModal();

        if(resultCode = mrYes) then begin
            selectedEdid := trim(plotEdidInput.Text);
            potentialTarget := FindObjectByEdid(selectedEdid);
            if(assigned(potentialTarget)) then begin
                targetScript := getScript(potentialTarget, 'SimSettlementsV2:Weapons:BuildingPlan');
                if(assigned(targetScript)) then begin
                    Result := potentialTarget;
                end else begin
                    AddMessage('ERROR: Selected target building plan '+selectedEdid+' is not valid. It must have the script SimSettlementsV2:Weapons:BuildingPlan');
                end;
            end else begin
            AddMessage('ERROR: failed to find any form for EditorID '+selectedEdid);
            end;
        end;

        frm.free();
        plotDialogOkBtn := nil;
    end;

    function getNewVersionOfPlot(oldPlot: IInterface): IInterface;
    var
        oldEdid, newSig, newEdid: string;
		mappingIndex: integer;
    begin
        oldEdid := EditorID(oldPlot);
		// there might be mapping specified
		AddMessage('Checking '+oldEdid);
		if(nil <> plotMapping) then begin
			mappingIndex := plotMapping.indexOf(oldEdid);
			if(mappingIndex >= 0) then begin
				Result := ObjectToElement(plotMapping.Objects[mappingIndex]);
				exit;
			end;
		end;

        // it might exist in the cache
        Result := getPlotFromCache(oldEdid);
        if(assigned(Result)) then exit;

        newSig := 'WEAP';
        newEdid := GenerateEdid(buildingPlanPrefix, oldEdid);

        // see if it exists in the target file with oldEdid, or newEdid, or if it exists in SS2.esm with either edid
        Result := MainRecordByEditorID(GroupBySignature(ss2masterFile, newSig), oldEdid);
        if(assigned(Result)) then exit;
        Result := MainRecordByEditorID(GroupBySignature(ss2masterFile, newSig), newEdid);
        if(assigned(Result)) then exit;

        Result := MainRecordByEditorID(GroupBySignature(targetFile, newSig), oldEdid);
        if(assigned(Result)) then exit;
        Result := MainRecordByEditorID(GroupBySignature(targetFile, newSig), newEdid);
        if(assigned(Result)) then exit;

        Result := nil;
    end;

    function processBuildingPlan(e: IInterface): boolean;
    var
        script, extraInfo, newRoot, formList, descrOmod, confirmMesg: IInterface;
        newScript: IInterface;
        bpEdId, planEditBase, oldDesc, newDesc, newConfirm, oldName: string;
        buildPlanPaths: IInterface;
        subType: integer;
    begin
        Result := false;
        script := getScript(e, 'SimSettlements:SimBuildingPlan');
        if(not assigned(script)) then begin
            exit;
        end;
        Result := true;

        // check for being part of an IR tree
        //if (getScriptPropDefault(script, 'TechTreeName', '') <> '') then begin
        if (isPartOfBranchingBlueprint(e)) then begin
            // maybe also check this?
            // ElementCount(getScriptProp(oldScript, 'LevelStops')) = 1
            // part of a tech tree, ignore
            AddMessage('Plot '+EditorID(e)+' is part of a branching blueprint, skipping until the master is encountered');
            exit;
        end;

        if(not ShowPlotConversionDialog(e)) then begin
            exit;
        end;

        applyLevelPlanOffsets(oldPlotType);

        sourceFile := GetFile(e);
        loadValidMastersFromFile(sourceFile);


        buildPlanPaths := getScriptProp(script, 'BuildPlanPaths');

        if(assigned(buildPlanPaths)) then begin
            processBranchingBuildingPlan(e, script, buildPlanPaths);
            exit;
        end;

        planEditBase := StripPrefix(buildingPlanPrefix, StripPrefix(oldFormPrefix, EditorID(e)));

        AddMessage('Converting normal blueprint '+GetElementEditValues(e, 'FULL')+' '+EditorID(e));

        extraInfo := getScriptProp(script, 'ExtraPlaqueInfo');

        bpEdId := GenerateEdid(buildingPlanPrefix, planEditBase);

        oldName := GetElementEditValues(e, 'FULL - Name');
        oldDesc := GetElementEditValues(extraInfo, 'DESC - Description');
        oldDesc := trim(StringReplace(oldDesc, STRING_LINE_BREAK + STRING_LINE_BREAK, STRING_LINE_BREAK, [rfReplaceAll]));


        subType  := extractPlotSubtype(currentPlotType);

        newDesc := getSubtypeDescriptionString(subType) + oldDesc;
        newConfirm := oldName + STRING_LINE_BREAK + oldDesc;

        newRoot := prepareBlueprintRoot(targetFile, nil, bpEdId, oldName, newDesc, newConfirm);

        convertStages(e, newRoot, planEditBase);
		AddMessage('Converting Stages finished');
		// Make sure main BP has appropriate prefix
		// SetElementEditValues(newRoot, 'EDID', bpEdId);

        // register it
        finalizePlot(e, newRoot, currentPlotType);

        AddMessage('Converting finished.');
    end;

	function getFromFromOldSpawnStruct(oldStruct: IInterface): IInterface;
	var
		curFormId: cardinal;
		curFileName: string;
	begin
		Result := getStructMember(oldStruct, 'FormToSpawn');
		if(assigned(Result)) then begin
			exit;
		end;

		// try formID/filename
		curFormId := getStructMemberDefault(oldStruct, 'iExternalFormID', 0);
		curFileName := getStructMemberDefault(oldStruct, 'sExternalPlugin', '');
		if(curFormId > 0) and (curFileName <> '') then begin
			Result := getFormByFilenameAndFormID(curFileName, curFormId);
		end;
	end;

    procedure processSkinLevelItems(forLevel: integer; oldItemArray, newLevelSkinScript: IInterface; propertyName, edidBase: string);
    var
        j, curLevel: integer;
        curOld, newArray, newStruct, newItemSpawn, formToSpawn, oldForm: IInterface;
        itemSpawnEdid: string;
    begin

        for j:=0 to ElementCount(oldItemArray)-1 do begin
            curOld := ElementByIndex(oldItemArray, j);
            curLevel := getStructMemberDefault(curOld, 'iLevel', 0);

            if(curLevel = forLevel) then begin
                newArray := getOrCreateScriptProp(newLevelSkinScript, propertyName, 'Array of Struct');

                newStruct := appendStructToProperty(newArray);
{
                itemSpawnEdid := generateStageItemEdid(
                    EditorID(formToSpawn),
                    stripPrefix(oldFormPrefix, edidBase),
                    IntToStr(forLevel)+'_'+IntToStr(j),
                    ''
                );

				oldForm := getFromFromOldSpawnStruct(curOld);

				if(not assigned(oldForm)) then begin
					AddMessage('WARNING: failed to find spawn #'+IntToStr(j)+' in level '+IntToStr(forLevel));
					continue;
				end;

                formToSpawn := translateForm(oldForm);
                newItemSpawn := createStageItemForm(
                    targetFile,
                    itemSpawnEdid,
                    formToSpawn,
                    getStructMemberDefault(curOld, 'fOffsetX', 0.0),//+levelPlanOffsetX,
                    getStructMemberDefault(curOld, 'fOffsetY', 0.0),//+levelPlanOffsetY,
                    getStructMemberDefault(curOld, 'fOffsetZ', 0.0),//+levelPlanOffsetZ,
                    getStructMemberDefault(curOld, 'fRotationX', 0.0),
                    getStructMemberDefault(curOld, 'fRotationY', 0.0),
                    getStructMemberDefault(curOld, 'fRotationZ', 0.0),
                    getStructMemberDefault(curOld, 'fScale', 1.0),
                    getStructMemberDefault(curOld, 'iType', 0.0),
                    '',
                    nil
                );
}
                newItemSpawn := getNewStageItem2(edidBase, IntToStr(forLevel)+'_'+IntToStr(j), curOld, 0, 0, 0);
                //edid, suffix: string; oldSpawnEntry: IInterface; offsetX, offsetY, offsetZ: float): IInterface;

                //newItemSpawn := getNewStageItem();
                setStructMember(newStruct, 'StageItemDetails', newItemSpawn);
                // curOld is a LevelItemSpawn

            end;
        end;

    end;

    procedure processSkinRequirements(oldScript, newScript: IInterface; edidBase: string);
    var
        reqEdid, otherPluginName: string;
        hasFactionRefs: boolean;
        CompletedQuestStages, usageReqs, usageReqsScript, curQuestStage, QuestRequirements, questToCheck, newQuestStageSet: IInterface;
        i, questStage: integer;
        otherFormId: cardinal;
    begin
        hasFactionRefs := false;//for now getScriptPropDefault(oldScript, 'bOwningFactionRequired', false);
        CompletedQuestStages := getScriptPropDefault(oldScript, 'CompletedQuestStages', nil);
        if (not hasFactionRefs) and (not assigned(CompletedQuestStages)) then begin
            exit;
        end;

        // generate the misc
        reqEdid := GenerateEdid(buildingSkinPrefix+'Req_', edidBase);
        usageReqs := getCopyOfTemplate(targetFile, usageReqsTemplate, reqEdid);
        usageReqsScript := getScript(usageReqs, 'SimSettlementsV2:MiscObjects:UsageRequirements');

        if(hasFactionRefs) then begin
            //?
        end;

        if(assigned(CompletedQuestStages)) then begin
            QuestRequirements := getOrCreateScriptProp(usageReqsScript, '', 'Array of Struct');
            QuestRequirements := getValueAsVariant(QuestRequirements, nil);

            for i:=0 to ElementCount(CompletedQuestStages)-1) do begin
                curQuestStage := ElementByIndex(CompletedQuestStages, i);

                newQuestStageSet := appendStructToProperty(QuestRequirements);

                questStage := getScriptPropDefault(curQuestStage, 'iStage', 0);
                otherPluginName := getScriptPropDefault(curQuestStage, 'sPlugin', '');
                otherFormId := getScriptPropDefault(curQuestStage, 'iFormID', 0);
                questToCheck := getScriptProp(curQuestStage, 'QuestToCheck');
                if(assigned(questToCheck)) then begin
                    setScriptProp(newQuestStageSet, 'iStage', questStage);
                    if(assigned(questToCheck)) then begin
                        setScriptProp(newQuestStageSet, 'QuestForm', questToCheck);
                    end else begin
                        setScriptProp(newQuestStageSet, 'iFormID', otherFormId);
                        setScriptProp(newQuestStageSet, 'sPluginName', otherPluginName);
                    end;
                end;
            end;
        end;
    end;

    function processBuildingPlanSkin(e: IInterface): boolean;
    var
        targetPlotEdid, externalTargetFilename, oldDescr, rootEdid: string;
        oldScript, oldTarget, oldExternalForm, oldItemSpawnExtra, oldItemSpawnReplace, oldStageModelReplace, curOld, oldStageModel: IInterface;
        newTarget, newRoot, newScript, newDescription, currentLevelSkin, currentLevelScript, newStageModel, levelTarget, levelSkinsArray: IInterface;
        oldExternalFormId: cardinal;
        isPlayerSelect, foundTheModel: boolean;
        i,j, curLevel, newPlotType, guessedPlotType: integer;
        configuredForLevels: array[1..4] of integer;
    begin
        Result := false;
        foundTheModel := false;

        oldScript := getScript(e, 'SimSettlements:SimBuildingPlanSkin');
        if(not assigned(oldScript)) then begin
            exit;
        end;

        sourceFile := GetFile(e);
        loadValidMastersFromFile(sourceFile);

        // find the target plot
        oldTarget := getScriptProp(oldScript, 'TargetBuildingPlanForm');
        if(not assigned(oldTarget)) then begin
            // try the external form
            oldExternalForm := getScriptProp(oldScript, 'TargetBuildingPlanForm');
            if(not assigned(oldExternalForm)) then begin
                AddMessage('This skin doesn''t point to any plot');
                exit;
            end;
            externalTargetFilename := getStructMemberDefault(oldExternalForm, '');
            oldExternalFormId := getStructMemberDefault(oldExternalForm, -1);
            if (externalTargetFilename = '') or (oldExternalFormId <= 0) then begin
                AddMessage('This skin doesn''t point to any plot');
                exit;
            end else begin
                oldTarget := getFormByFilenameAndFormID();
                if(not assigned(oldTarget)) then begin
                    AddMessage('Couldn''t find external form '+externalTargetFilename+':'+IntToHex(oldExternalFormId, 8));
                    exit;
                end;
            end;
        end;

        // try to convert the old one
        guessedPlotType := guessPlotType(oldTarget);

        newTarget := getNewVersionOfPlot(oldTarget);
        if(not assigned(newTarget)) then begin
            newTarget := selectSkinTargePlot(e, oldTarget);
            if(not assigned(newTarget)) then begin
                AddMessage('Could not find new version of '+EditorID(oldTarget)+', this skin will not be converted');
                exit;
            end;
        end;

        // get new plot type!
        newPlotType := getNewPlotType(newTarget);
        if(newPlotType = -1) then begin
            AddMessage('Could not find type of plot '+EditorID(newTarget));
            exit;
        end;

        // apply offsets
        if(guessedPlotType >= 0) then begin
            applyLevelPlanOffsets(guessedPlotType);
        end;

        Result := true;

        AddMessage('Converting Building Skin "'+DisplayName(e)+'" for "'+DisplayName(oldTarget)+'"');
        rootEdid := GenerateEdid(buildingSkinPrefix, EditorID(e)+'_root');
        oldDescr := GetElementEditValues(e, 'FULL');

        newRoot := prepareSkinRoot(targetFile, nil, newTarget, GenerateEdid(buildingSkinPrefix, EditorID(e)), oldDescr);

        newScript := getScript(newRoot, 'SimSettlementsV2:Weapons:BuildingSkin');

        // copy over the simple stuff

        isPlayerSelect := getScriptProp(oldScript, 'bPlayerSelectOnly');
        if(isPlayerSelect) then begin
            setScriptProp(newScript, 'bPlayerSelectOnly', true);
        end;

        oldItemSpawnExtra := getScriptProp(oldScript, 'AdditionalStageItemSpawns');
        oldItemSpawnReplace := getScriptProp(oldScript, 'ReplaceStageItemSpawns');
        oldStageModelReplace := getScriptProp(oldScript, 'ReplaceStageModels');

        // figure out which levels this skin handles
        configuredForLevels[1] := 0;
        configuredForLevels[2] := 0;
        configuredForLevels[3] := 0;
        configuredForLevels[4] := 0;

        if(assigned(oldItemSpawnExtra)) then begin
            for j:=0 to ElementCount(oldItemSpawnExtra)-1 do begin
                curOld := ElementByIndex(oldItemSpawnExtra, j);

                curLevel := getStructMemberDefault(curOld, 'iLevel', 0);
                if (curLevel >= 1) and (curLevel <= 4) then begin
                    configuredForLevels[curLevel] := 1;
                end;
            end;
        end;

        if(assigned(oldItemSpawnReplace)) then begin
            for j:=0 to ElementCount(oldItemSpawnReplace)-1 do begin
                curOld := ElementByIndex(oldItemSpawnReplace, j);
                curLevel := getStructMemberDefault(curOld, 'iLevel', 0);
                if (curLevel >= 1) and (curLevel <= 4) then begin
                    configuredForLevels[curLevel] := 1;
                end;
            end;
        end;

        if(assigned(oldStageModelReplace)) then begin
            for j:=0 to ElementCount(oldStageModelReplace)-1 do begin
                curOld := ElementByIndex(oldStageModelReplace, j);
                curLevel := getStructMemberDefault(curOld, 'iLevel', 0);

                if (curLevel >= 1) and (curLevel <= 4) then begin
                    configuredForLevels[curLevel] := 1;
                end;
            end;
        end;

        // usage requirements
        processSkinRequirements(oldScript, newScript, rootEdid);


        for i:=1 to 4 do begin
            if (configuredForLevels[i] = 1) then begin

                levelTarget := getLevelBuildingPlan(newTarget, i);
                if(not assigned(levelTarget)) then begin
                    AddMessage('Can''t convert Level '+IntToStr(i)+' of skin '+rootEdid+': could not find that level in the target plot');
                    break;
                end;

                currentLevelSkin := getOrCreateSkinForLevel(targetFile, newRoot, i);
                SetElementEditValues(currentLevelSkin, 'FULL', getElementEditValues(newRoot, 'FULL')+' Level '+IntToStr(i));
                currentLevelScript := getScript(currentLevelSkin, 'SimSettlementsV2:Weapons:BuildingLevelSkin');

                // reset them, just for rerunability
                clearScriptProperty(currentLevelScript, 'AdditionalStageItemSpawns');
                cleanItemSpawns(getRawScriptProp(currentLevelScript, 'ReplaceStageItemSpawns'));
                cleanItemSpawns(getRawScriptProp(currentLevelScript, 'ReplaceStageModel'));

                setScriptProp(currentLevelScript, 'TargetBuildingLevelPlan', levelTarget);
                setScriptProp(currentLevelScript, 'ParentBuildingSkin', newRoot);

                // find the stage model replace
                if(assigned(oldStageModelReplace)) then begin

                    for j:=0 to ElementCount(oldStageModelReplace)-1 do begin
                        curOld := ElementByIndex(oldStageModelReplace, j);
                        curLevel := getStructMemberDefault(curOld, 'iLevel', 0);

                        if(curLevel = i) then begin
                            oldStageModel := getStructMember(curOld, 'ModelForm');

                            if(assigned(oldStageModel)) then begin
                                newStageModel := translateForm(oldStageModel);
                                //dumpElem(newStageModel);
                                if(assigned(newStageModel)) then begin
                                    // AddMessage('Got New StageModel');

                                    addToStackEnabledListIfEnabled(newStageModel);

									setScriptProp(currentLevelScript, 'ReplaceStageModel', newStageModel);

                                    if(not foundTheModel) then begin
                                        // set model to newRoot
                                        if(makePreviews) then begin
                                            if(Signature(newStageModel) <> 'SCOL') then begin
                                                applyModel(newStageModel, newRoot);
                                            end;
                                        end;
                                        foundTheModel := true;
                                    end;

                                end;
                            end;
                        end;
                    end;
                end;

                // procedure processSkinLevelItems(forLevel: integer; oldItemArray, newLevelSkinScript: IInterface; propertyName: string);
                if(assigned(oldItemSpawnExtra)) then begin
                    processSkinLevelItems(i, oldItemSpawnExtra, currentLevelScript, 'AdditionalStageItemSpawns', rootEdid+'_additional_');
                end;

                if(assigned(oldItemSpawnReplace)) then begin
                    processSkinLevelItems(i, oldItemSpawnReplace, currentLevelScript, 'ReplaceStageItemSpawns', rootEdid+'_replace_');
                end;
            end;
        end; // of for

        registerSkin(newRoot, newPlotType);

    end;

    {
        Finds a COBJ by FVPA = requred components
    }
    function findFurnitureCobj(misc: IInterface): IInterface;
    var
        i, j: integer;
        numRefs: cardinal;
        curRef, curCnam, fvpa, curFvpa, curComponent: IInterface;
    begin
        numRefs := ReferencedByCount(misc);

        for i:=0 to numRefs-1 do begin
            curRef := ReferencedByIndex(misc, i);
            fvpa := ElementByPath(curRef, 'FVPA');

            for j:=0 to ElementCount(fvpa)-1 do begin
                curFvpa := ElementByIndex(fvpa, j);
                curComponent := LinksTo(ElementByPath(curFvpa, 'Component'));

                if(isSameForm(curComponent, misc)) then begin
                    Result := curRef;
                    exit;
                end;
            end;
        end;
    end;

    {
        Finds a COBJ by CNAM
    }
    function findCobjByResult(misc: IInterface): IInterface;
    var
        i, j: integer;
        numRefs: cardinal;
        curRef, curCnam, fvpa, curFvpa, curComponent: IInterface;
    begin
        numRefs := ReferencedByCount(misc);

        for i:=0 to numRefs-1 do begin
            curRef := ReferencedByIndex(misc, i);
            if(signature(curRef) = 'COBJ') then begin
                curCnam := PathLinksTo(curRef, 'CNAM');

                if(isSameForm(curCnam, misc)) then begin
                    Result := curRef;
                    exit;
                end;
            end;
        end;
    end;

    function processFurniture(e: IInterface): boolean;
    var
        oldScript, oldTrns, oldObject, oldCobj: IInterface;
        newMisc, newScript, newTrns, newObject: IInterface;
        oldEdid, newEdidBase: string;
        oldLevel: integer;
    begin
        oldScript := getScript(e, 'SimSettlements:FurnitureStoreItem');
        if(not assigned(oldScript)) then begin
            Result := false;
            exit;
        end;
        sourceFile := GetFile(e);
        loadValidMastersFromFile(sourceFile);
        AddMessage('Converting Furniture Store Item '+DisplayName(e));

        Result := true;

        oldObject := getScriptProp(oldScript, 'WorldObject');
        oldCobj := findFurnitureCobj(e);
        //AddMessage('Found this OldCobj:');
        //dumpElem(oldCobj);
        // in theory, this can be missing
        if(not assigned(oldObject)) then begin

            oldObject := pathLinksTo(oldCobj, 'CNAM');
        end;

        if(not assigned(oldObject)) then begin
            AddMessage('Found no world object for '+FullPath(e)+', can''t convert this.');
            exit;
        end;


        oldEdid := EditorID(e);

        newEdidBase := stripPrefix(oldFormPrefix, oldEdid);


        // template: SS2_PurchaseableFurniture_Template
        newMisc := getCopyOfTemplate(targetFile, SS2_PurchaseableFurniture_Template, generateEdid(furnItemPrefix, newEdidBase));

        newScript := getScript(newMisc, 'SimSettlementsV2:MiscObjects:FurnitureStoreItem');


        // AddMessage('NewMisc is');
        // dumpElem(newMisc);

        addRequiredMastersSilent(e, targetFile);
        applyModelAndTranslate(e, newMisc, sourceFile, targetFile);

        SetElementEditValues(newMisc, 'FULL', getElementEditValues(e, 'FULL'));

        oldTrns := pathLinksTo(e, 'PTRN');
        if(assigned(oldTrns)) then begin
            newTrns := translateForm(oldTrns);

            if(assigned(newTrns)) then begin
                setPathLinksTo(newMisc, 'PTRN', newTrns);
            end;
        end;
        newObject := translateForm(oldObject);

        // old props:
        {
        Form Property WorldObject Auto Const
        // The actual furniture item the player will build
        bool Property bCanBeDisplayed = True Auto Const
        // This item can be displayed physically at furniture stores when available. If your item displays strangely, such as overlapping or sinking too far, uncheck this.
        int Property iLevel = 1 Auto Const
        // The level of store you want this item to be available for sale. Should be 1, 2, or 3
        bool Property bFloorItem = True Auto Const
        // If the item is meant to go on a surface (such as a lamp, or decorative item), uncheck this
        }

        oldLevel := getScriptPropDefault(oldScript, 'iLevel', 1);

        setScriptPropDefault(newScript, 'iVendorLevel', oldLevel, 1);

        setUniversalForm(newScript, 'DisplayVersion', newObject);

        // new props:
        // UniversalForm Property DisplayVersion Auto Const
        // Int Property iPositionGroup = 0 Auto Const // probably best not to set
        {
        This will determine what types of markers this item can appear on in for sale.
        0 = Do Not Display;
        1 = Small Footprint Floor (lamp or small end table);
        2 = Medium Footprint Floor (dresser or large chair);
        3 = Large Footprint Floor (table or single bed);
        4 = XL Footprint Floor (double bed or large couch);
        5 = Small Surface (table lamp);
        6 = Medium Surface (tabletop television or terminal);
        7 = Large Surface (table cloth or planter box);
        8 = Small Wall Decoration (wall clock or small picture);
        9 = Medium Wall Decoration (poster size); 10 = Large Wall Decoration (large painting or theatre poster);
        10 = Small Ceiling (hanging lightbulb);
        11 = Medium Ceiling (Disco Ball);
        12 = Large Ceiling (chandelier)
        }
        // Int Property iVendorLevel = 1 Auto Const


        // now do COBJs
        createFurnitureCobjs(targetFile, newEdidBase, newMisc, newObject);

        registerConvertedContent(newMisc, SS2_FLID_FurnitureStoreItems);
    end;

    {
        Results:
        1, 2, 3: the sizes
        -2: 2x2, offsetted
        0: something weird
    }
    function findOldFoundationType(oldTfMisc: IInterface): integer;
    var
        i, j: integer;
        curFlst, curQust, qustScript: IInterface;
        propName: string;
    begin
        Result := 0;

        for i:=0 to ReferencedByCount(oldTfMisc)-1 do begin

            curFlst := ReferencedByIndex(oldTfMisc, i);
            if(Signature(curFlst) = 'FLST') then begin

                for j:=0 to ReferencedByCount(curFlst)-1 do begin
                    curQust := ReferencedByIndex(curFlst, j);

                    if (Signature(curQust) = 'QUST') then begin

                        qustScript := getScript(curQust, 'SimSettlements:AddOnScript');
                        if(assigned(qustScript)) then begin
                            // now find out where exactly curFlst is
                            propName := findPropertyContainingObject(qustScript, curFlst);

                            if
                                (propName = 'MyFoundations_Agricultural2x2') or
                                (propName = 'MyFoundations_Commercial2x2') or
                                (propName = 'MyFoundations_Industrial2x2') or
                                (propName = 'MyFoundations_Residential2x2')
                            then begin
                                Result := -2;
                                exit;
                            end;

                            if(propName = 'MyFoundations_Martial1x1') then begin
                                Result := 1;
                                exit;
                            end;

                            if
                                (propName = 'MyFoundations_Martial2x2') or
                                (propName = 'MyFoundations_IndustrialAdvanced2x2') or
                                (propName = 'MyFoundations_Recreational2x2')
                            then begin
                                Result := 2;
                                exit;
                            end;

                            if(propName = 'MyFoundations_Agricultural3x3') then begin
                                Result := 3;
                                exit;
                            end;
                        end;
                    end;
                end;
            end;
        end;
    end;

    function getObjectCobj(e: IInterface): IInterface;
    var
        i: integer;
        curRef, curCnam: IInterface;
    begin
        Result := nil;

        for i:=0 to ReferencedByCount(e)-1 do begin
            curRef := ReferencedByIndex(e, i);
            if(Signature(curRef) = 'COBJ') then begin
                curCnam := PathLinksTo(curRef, 'CNAM');
                if(isSameForm(curCnam, e)) then begin
                    Result := curRef;
                    exit;
                end;
            end;
        end;
    end;

    {
        applies data like name, description, components from oldCobj to newCobj
    }
    procedure applyCobjData(oldCobj, newCobj: IInterface);
    var
        oldAnam, oldComponents, oldCmpEntry, oldCurCmp, newComponents, newCmpEntry, newCurCmp: IInterface;
        oldPrio, oldDesc: string;
        hasOverwrittenFirst: boolean;
        i, curCount: integer;
    begin
        // setPathLinksTo(newCobj, 'CNAM', craftResult);

        oldAnam := pathLinksTo(oldCobj, 'ANAM');

        if(assigned(oldAnam)) then begin
            setPathLinksTo(newCobj, 'ANAM', oldAnam);
        end else begin
            RemoveElement(newCobj, 'ANAM');
        end;

        oldPrio := GetElementEditValues(oldCobj, 'INTV\Priority');
        if(oldPrio <> '') and(oldPrio <> '0') then begin
            SetElementEditValues(newCobj, 'INTV\Priority', oldPrio);
        end;

        oldDesc := GetElementEditValues(oldCobj, 'DESC');
        if(oldDesc <> '') then begin
            SetElementEditValues(newCobj, 'DESC', oldDesc);
        end;

        oldComponents := ElementByPath(oldCobj, 'FVPA');

        RemoveElement(newCobj, 'FVPA');
        Add(newCobj, 'FVPA', true);

        newComponents := ElementByPath(newCobj, 'FVPA');

        hasOverwrittenFirst := false;
        for i:=0 to ElementCount(oldComponents)-1 do begin
            oldCmpEntry := ElementByIndex(oldComponents, i);

            oldCurCmp := pathLinksTo(oldCmpEntry, 'Component');
            curCount := StrToInt(GetElementEditValues(oldCmpEntry, 'Count'));
            newCurCmp := translateForm(oldCurCmp);
            if(not assigned(newCurCmp)) then begin
                continue;
            end;

            if(not hasOverwrittenFirst) then begin
                newCmpEntry := ElementByIndex(newComponents, 0);
                hasOverwrittenFirst := true;
            end else begin
                newCmpEntry := ElementAssign(newComponents, HighInteger, nil, False);
            end;

            setPathLinksTo(newCmpEntry, 'Component', newCurCmp);
            SetElementEditValues(newCmpEntry, 'Count', IntToStr(curCount));
        end;
    end;

    function createFoundationCobj(edidBase: string; foundation, oldCobj: IInterface): IInterface;
    var
        oldMenuArt, oldComponents, oldCmpEntry, oldCurCmp, newComponents, newCmpEntry, newCurCmp, newMenuArt: IInterface;
        i, curCount: integer;
        oldPrio: string;
        hasOverwrittenFirst: boolean;
    begin
        //foundationTemplate_Cobj
        Result := getCopyOfTemplate(targetFile, foundationTemplate_Cobj, generateEdid(foundationPrefix, edidBase+'_COBJ'));

        oldPrio := 0;
// AddMessage('Would set cnam to '+FullPath(foundation));
        setPathLinksTo(Result, 'CNAM', foundation);

        if(not assigned(oldCobj)) then begin
            RemoveElement(Result, 'ANAM');
            exit;
        end;

        applyCobjData(oldCobj, Result);
        {
        oldPrio := GetElementEditValues(oldCobj, 'INTV\Priority');
        if(oldPrio <> '') and(oldPrio <> '0') then begin
            SetElementEditValues(Result, 'INTV\Priority', oldPrio);
        end;

        oldMenuArt := pathLinksTo(oldCobj, 'ANAM');
        if(assigned(oldMenuArt)) then begin
            newMenuArt := translateForm(oldMenuArt);
        end;

        if(assigned(newMenuArt)) then begin
            setPathLinksTo(Result, 'ANAM', newMenuArt);
        end else begin
            RemoveElement(Result, 'ANAM');
        end;


        oldComponents := ElementByPath(oldCobj, 'FVPA');

        RemoveElement(Result, 'FVPA');
        Add(Result, 'FVPA', true);

        newComponents := ElementByPath(Result, 'FVPA');

        hasOverwrittenFirst := false;
        for i:=0 to ElementCount(oldComponents)-1 do begin
            oldCmpEntry := ElementByIndex(oldComponents, i);

            oldCurCmp := pathLinksTo(oldCmpEntry, 'Component');
            curCount := StrToInt(GetElementEditValues(oldCmpEntry, 'Count'));
            newCurCmp := translateForm(oldCurCmp);
            if(not assigned(newCurCmp)) then begin
                continue;
            end;

            if(not hasOverwrittenFirst) then begin
                newCmpEntry := ElementByIndex(newComponents, 0);
                hasOverwrittenFirst := true;
            end else begin
                newCmpEntry := ElementAssign(newComponents, HighInteger, nil, False);
            end;

            setPathLinksTo(newCmpEntry, 'Component', newCurCmp);
            SetElementEditValues(newCmpEntry, 'Count', IntToStr(curCount));
        end;
        }
    end;

    function convertPackedDeskVersion(edidBase: string; oldPackedVersion, newDesk: IInterface): IInterface;
    var
        oldScript: IInterface;
        newObj, newScript: IInterface;
        newEdid: string;
    begin
        Result := nil;
        // old script: SimSettlements:DeployableCityPlannersDesk
        // new script: SimSettlementsV2:ObjectReferences:DeployableCityPlannersDesk
        oldScript := getScript(oldPackedVersion, 'SimSettlements:DeployableCityPlannersDesk');
        if(not assigned(oldScript)) then exit;

        newEdid := GenerateEdid(deskPrefix+'packed_', edidBase);

        newObj := getCopyOfTemplate(targetFile, oldPackedVersion, newEdid);

        newScript := getScript(newObj, 'SimSettlements:DeployableCityPlannersDesk');

        // could mean that this has been converted already
        if(not assigned(newScript)) then exit;

        SetElementEditValues(newScript, 'ScriptName', 'SimSettlementsV2:ObjectReferences:DeployableCityPlannersDesk');
        deleteScriptProps(newScript);

        setScriptProp(newScript, 'CityPlannersDesk', newDesk);

        // postprocessing for matswaps and such
        findFormIds(newObj, sourceFile, targetFile);

        Result := newObj;
    end;

    function translateDeskSpawnObject(oldSpawn: IInterface): IInterface;
    var
        oldSpawnFile, oldScripts, oldScript: IInterface;
        newObj: IInterface;
        i: integer;
        curScriptName, newEdid: string;
        isFlagUp: boolean;
        oldFlagMode, oldEdid: string;
    begin
        Result := translateForm(oldSpawn);
        exit; // DEBUG!


        Result := oldSpawn;
        oldSpawnFile := GetFile(oldSpawn);
        if(not FilesEqual(oldSpawnFile, sourceFile)) then begin
            // do some default stuff
            Result := translateForm(oldSpawn);
            exit;
        end;

        oldEdid := EditorID(oldSpawn);

        newEdid := GenerateEdid('', stripPrefix(oldFormPrefix, oldEdid));
        newObj := getCopyOfTemplate(targetFile, oldSpawn, newEdid);
        oldScripts := ebp(newObj, 'VMAD - Virtual Machine Adapter\Scripts');

        for i:=0 to ElementCount(oldScripts)-1 do begin
            oldScript := ElementByIndex(oldScripts, i);
            curScriptName := geevt(oldScript, 'ScriptName');

            if(curScriptName = 'SimSettlements:CityPlannerDeskDrawer') then begin
                // this is a building plans drawer
                SetElementEditValues(oldScript, 'ScriptName', 'SimSettlementsV2:ObjectReferences:LeaderDeskObject_ThemeDrawer');
                deleteScriptProps(oldScript);
                SetElementEditValues(newObj, 'FULL', 'Building Plans');
                SetElementEditValues(newObj, 'ATTX', 'Setup Themes');
                break;
                {
                SimSettlements:CityPlannerDeskDrawer > SimSettlementsV2:ObjectReferences:LeaderDeskObject_ThemeDrawer
                    - No properties needed on new script
                    - Name Field: Building Plans
                    - Activate Text Override: Setup Themes
                }
            end;

            if(curScriptName = 'SimSettlements:CityPlannerDeskBlueprint') then begin
                // this is a building plans drawer
                SetElementEditValues(oldScript, 'ScriptName', 'SimSettlementsV2:ObjectReferences:LeaderDeskObject_CityPlanManager');
                deleteScriptProps(oldScript);
                SetElementEditValues(newObj, 'FULL', 'Manage City');
                break;

                {
                SimSettlements:CityPlannerDeskBlueprint > SimSettlementsV2:ObjectReferences:LeaderDeskObject_CityPlanManager
                    - No properties needed on new script
                    - Name Field: Manage City
                }
            end;

            if(curScriptName = 'SimSettlements:CitySupplies') then begin
                // this is a building plans drawer
                SetElementEditValues(oldScript, 'ScriptName', 'SimSettlementsV2:ObjectReferences:LeaderDeskObject_Supplies');
                deleteScriptProps(oldScript);
                SetElementEditValues(newObj, 'FULL', 'City Supplies');
                SetElementEditValues(newObj, 'ATTX', 'Manage');
                break;
                {
                SimSettlements:CitySupplies > SimSettlementsV2:ObjectReferences:LeaderDeskObject_Supplies
                    - No properties needed on new script
                    - Name Field: City Supplies
                    - Activate Text Override: Manage
                }
            end;

            if(curScriptName = 'SimSettlements:FlagSelector') then begin
                // this is a building plans drawer
                SetElementEditValues(oldScript, 'ScriptName', 'SimSettlementsV2:ObjectReferences:LeaderDeskObject_FlagSelector');

                // this needs props!
                oldFlagMode := getScriptPropDefault(oldScript, 'iFlagModel', 'Up');
                isFlagUp := getScriptPropDefault(oldScript, 'FlagUp', true);

                deleteScriptProps(oldScript);

                if (isFlagUp) or (oldFlagMode = 'Up') then begin
                    // up
                    setScriptProp(oldScript, 'ThemePropertyName', 'FlagWaving');
                    setScriptProp(oldScript, 'DefaultForm', flagTemplate_Waving);
                end else if(oldFlagMode = 'Wall') then begin
                    // wall
                    setScriptProp(oldScript, 'ThemePropertyName', 'FlagWall');
                    setScriptProp(oldScript, 'DefaultForm', flagTemplate_Wall);
                end else begin
                    // down
                    setScriptProp(oldScript, 'ThemePropertyName', 'FlagDown');
                    setScriptProp(oldScript, 'DefaultForm', flagTemplate_Down);
                end;
                setScriptProp(oldScript, 'ThemeScript', 'SimSettlementsV2:Armors:ThemeDefinition_Flags');
                setScriptProp(oldScript, 'ThemeRuleSet', SS2_ThemeRuleset_Flags);

                SetElementEditValues(newObj, 'FULL', 'Settlement Flag');
                SetElementEditValues(newObj, 'ATTX', 'Select Flag');
                break;
                {
                SimSettlements:FlagSelector -> SimSettlementsV2:ObjectReferences:LeaderDeskObject_FlagSelector
                    - DefaultForm: SS2_FlagDown_USA [STAT:03012BF3]
                    - ThemePropertyName: FlagDown (??) <- read from iFlagModel in old, find other values except 'Down'. there is also bool FlagUp=false
                    - ThemeRuleSet: SS2_ThemeRuleset_Flags "Flag Ruleset" [MISC:0301BB47]
                    - ThemeScript: SimSettlementsV2:Armors:ThemeDefinition_Flags
                    - Activate Text Override: Select Flag
                }
            end;
        end;

        findFormIds(newObj, sourceFile, targetFile);

        Result := newObj;
    end;

    procedure convertDeskSpawn(edidBase: string; oldSpawnStruct, newProp: IInterface);
    var
        externalFormId: cardinal;
        externalPluginName: string;
        formToSpawn, newFormToSpawn: IInterface;
        posX, posY, posZ, rotX, rotY, rotZ, scale: float;
        forceStatic: boolean;
        newSpawnStruct: IInterface;
    begin
        externalFormId := getStructMemberDefault(oldSpawnStruct, 'iExternalFormID', 0);
        externalPluginName := getStructMemberDefault(oldSpawnStruct, 'sExternalPlugin', '');
        formToSpawn := getStructMemberDefault(oldSpawnStruct, 'FormToSpawn', nil);

        posX := getStructMemberDefault(oldSpawnStruct, 'fOffsetX', 0.0);
        posY := getStructMemberDefault(oldSpawnStruct, 'fOffsetY', 0.0);
        posZ := getStructMemberDefault(oldSpawnStruct, 'fOffsetZ', 0.0);

        rotX := getStructMemberDefault(oldSpawnStruct, 'fRotationX', 0.0);
        rotY := getStructMemberDefault(oldSpawnStruct, 'fRotationY', 0.0);
        rotZ := getStructMemberDefault(oldSpawnStruct, 'fRotationZ', 0.0);

        scale := getStructMemberDefault(oldSpawnStruct, 'fScale', 1.0);

        forceStatic := getStructMemberDefault(oldSpawnStruct, 'bForceStatic', false);

        if(not assigned(formToSpawn)) then begin
            if(externalPluginName <> '') and (externalFormId > 0) then begin
                // maybe this can be used directly
                formToSpawn := getFormByFilenameAndFormID(externalPluginName, externalFormId);
                // if it's still unassigned, doesn't matter
            end else begin
                AddMessage('WARNING: Empty spawn in city planner''s desk');
                exit;
            end;
        end;

        if(assigned(formToSpawn)) then begin
            newFormToSpawn := translateDeskSpawnObject(formToSpawn);
            if(not assigned(newFormToSpawn)) then begin
                AddMessage('Failed to translate '+EditorID(formToSpawn)+', this city planner''s desk object will be skipped!');
                exit;
            end;
        end;

        newSpawnStruct := appendStructToProperty(newProp);

        // fill it into new struct
        if(assigned(newFormToSpawn)) then begin
            setStructMember(newSpawnStruct, 'ObjectForm', newFormToSpawn);
        end else begin
            setStructMember(newSpawnStruct, 'iFormID', externalFormId);
            setStructMember(newSpawnStruct, 'sPluginName', externalPluginName);
        end;

        setStructMemberDefault(newSpawnStruct, 'fPosX', posX, 0.0);
        setStructMemberDefault(newSpawnStruct, 'fPosY', posY, 0.0);
        setStructMemberDefault(newSpawnStruct, 'fPosZ', posZ, 0.0);

        setStructMemberDefault(newSpawnStruct, 'fAngleX', rotX, 0.0);
        setStructMemberDefault(newSpawnStruct, 'fAngleY', rotY, 0.0);
        setStructMemberDefault(newSpawnStruct, 'fAngleZ', rotZ, 0.0);

        setStructMemberDefault(newSpawnStruct, 'fScale', scale, 1.0);

        setStructMemberDefault(newSpawnStruct, 'bForceStatic', forceStatic, false);
        // new is:
        {
        Struct WorldObject
            Form ObjectForm = None
            // Form to be created. [Optional] Either this, or iFormID + sPluginName have to be set.
            Int iFormID = -1
            // Decimal conversion of the last 6 digits of a forms Hex ID. [Optional] Either this + sPluginName, or ObjectForm have to be set.
            String sPluginName = ""
            // Exact file name the form is from (ex. Fallout.esm). [Optional] Either this + iFormID, or ObjectForm have to be set.
            Float fPosX = 0.0
            Float fPosY = 0.0
            Float fPosZ = 0.0
            Float fAngleX = 0.0
            Float fAngleY = 0.0
            Float fAngleZ = 0.0
            Float fScale = 1.0

            Bool bForceStatic = false
        EndStruct
        }
    end;

    function processDesk(e: IInterface): boolean;
    var
        oldScript, dlcScript, oldPackedVersion, oldSpawnedStuff: IInterface;
        newDesk, newScript, newPackedVersion, workshopParent, curStruct, newSpawnsArray: IInterface;
        oldDeskCobj, oldPackedCobj, newDeskCobj, newPackedCobj: IInterface;
        i: integer;
        oldEdid, newEdid, edidBase: string;
    begin
        Result := false;
        oldScript := getScript(e, 'SimSettlements:CityPlannerDesk');//praSim:CityPlannerTerminal

        if(not assigned(oldScript)) then begin
            exit;
        end;

        AddMessage('Converting City Planner''s Desk '+FullPath(e));
        Result := true;
        sourceFile := GetFile(e);
        loadValidMastersFromFile(sourceFile);

        oldPackedVersion := getScriptProp(oldScript, 'PackedVersion');
        oldSpawnedStuff := getScriptProp(oldScript, 'DeskStuff');
        workshopParent := getScriptProp(oldScript, 'WorkshopParent');

        oldEdid := EditorID(e);
        edidBase := stripPrefix('Workbench_', stripPrefix(oldFormPrefix, oldEdid));
        newEdid := GenerateEdid(deskPrefix, edidBase);

        // do NOT actually translate the old desk
        newDesk := getCopyOfTemplate(targetFile, e, newEdid);

        newScript := getScript(newDesk, 'SimSettlements:CityPlannerDesk');
        if(not assigned(newScript)) then begin
            newScript := getScript(newDesk, 'SimSettlementsV2:ObjectReferences:LeaderDesk');
            if(not assigned(newScript)) then begin
                exit; // ..?
            end;
        end else begin
            // rename the script
            SetElementEditValues(newScript, 'ScriptName', 'SimSettlementsV2:ObjectReferences:LeaderDesk');
        end;
        dlcScript := getScript(newDesk, 'SimSettlements:CityPlannerDesk_DLCRelay');
        if (assigned(dlcScript)) then begin
            Remove(dlcScript); // maybe also RemoveElement
        end;

        // simple stuff
        removeKeywordByPath(newDesk, 'kgSIM_PreventAutoAssign', 'KWDA');
        //removeKeywordByPath(newDesk, 'kgSIM_Workbench_CityPlannersDesk', 'KWDA');

        ////SS2_Tag_ManagementDesk, SS2_Workbench_CityPlannersDesk, WSFW_DoNotAutoassign

        addRequiredMastersSilent(SS2_Tag_ManagementDesk, targetFile);
        addRequiredMastersSilent(WSFW_DoNotAutoassign, targetFile);
        addKeywordByPath(newDesk, SS2_Tag_ManagementDesk, 'KWDA');
        //addKeywordByPath(newDesk, SS2_Workbench_CityPlannersDesk, 'KWDA');
        addKeywordByPath(newDesk, WSFW_DoNotAutoassign, 'KWDA');


        newPackedVersion := convertPackedDeskVersion(edidBase, oldPackedVersion, newDesk);



        // remove all props
        deleteScriptProps(newScript);
        setScriptProp(newScript, 'WorkshopParent', workshopParent);
        if(assigned(newPackedVersion)) then begin
            setScriptProp(newScript, 'PackedVersion', newPackedVersion);
        end;

        // complicated stuff
        //AddMessage('oldSpawnedStuff: ');
        //dumpElem(oldSpawnedStuff);
        newSpawnsArray := getOrCreateScriptPropArrayOfStruct(newScript, 'ExtraActivators');
        for i:=0 to ElementCount(oldSpawnedStuff)-1 do begin
            curStruct := ElementByIndex(oldSpawnedStuff, i);
          //  AddMessage('curStruct: ');
            //dumpElem(curStruct);
            convertDeskSpawn(edidBase, curStruct, newSpawnsArray);
        end;


        // the COBJs
        oldDeskCobj := findCobjByResult(e);
        if(assigned(oldDeskCobj)) then begin
            newDeskCobj := getCopyOfTemplate(targetFile, deskBaseCobj, generateEdid(deskPrefix, edidBase+'_COBJ'));
            setPathLinksTo(newDeskCobj, 'CNAM', newDesk);
            applyCobjData(oldDeskCobj, newDeskCobj);
        end;

        if(assigned(newPackedVersion)) then begin
            newPackedCobj := getCopyOfTemplate(targetFile, packedDeskBaseCobj, GenerateEdid(deskPrefix+'packed_', edidBase+'_COBJ'));
            setPathLinksTo(newPackedCobj, 'CNAM', newPackedVersion);

            oldPackedCobj := findCobjByResult(e);
            if(assigned(oldPackedCobj)) then begin
                applyCobjData(oldPackedCobj, newPackedCobj);
            end;
        end;


        findFormIds(newDesk, sourceFile, targetFile);

        // findCobjByResult
    end;

    function getSS2TraitEdid(oldId: integer): string;
    var
        xeditWhat: integer;
    begin
        Result := '';

        xeditWhat := oldId;

        case (xeditWhat) of
            0: Result := 'SS2_LeaderTrait_Major_ExperiencedMayor'; // Experienced Mayor
            1: Result := 'SS2_LeaderTrait_Major_RobotMoraleOfficer'; // Robot Moral Officer
            2: Result := 'SS2_LeaderTrait_Minor_Handyman'; // Handyman
            3: Result := 'SS2_LeaderTrait_Weakness_Pacifist'; // Pacifist
            4: Result := 'SS2_LeaderTrait_Major_MinutemenOfficer'; // Minutemen Officer
            5: Result := 'SS2_LeaderTrait_Minor_Recruiter'; // Recruiter
            6: Result := 'SS2_LeaderTrait_Weakness_Overzealous'; // Overzealous
            7: Result := 'SS2_LeaderTrait_Major_Truthseeker'; // Truthseeker
            8: Result := 'SS2_LeaderTrait_Weakness_Rebel'; // Rebel
            9: Result := 'SS2_LeaderTrait_Weakness_SynthSympathizer'; // Synth Sympathizer
            10: Result := 'SS2_LeaderTrait_Major_InstituteAlly'; // Institute Ally
            11: Result := 'SS2_LeaderTrait_Major_BrotherhoodAlly'; // Brotherhood Ally
            12: Result := 'SS2_LeaderTrait_Major_RailroadAlly'; // Railroad Ally
            13: Result := 'SS2_LeaderTrait_Minor_Futurist'; // Futurist
            14: Result := 'SS2_LeaderTrait_Weakness_HealthyAppetite'; // Inhospitable
            15: Result := 'SS2_LeaderTrait_Major_BotFinder'; // Bot Finder
            16: Result := 'SS2_LeaderTrait_Minor_Scavenger'; // Scavenger
            17: Result := 'SS2_LeaderTrait_Major_ExpertHunter'; // Hunter
            18: Result := 'SS2_LeaderTrait_Minor_AnimalLover'; // Animal Lover
            19: Result := 'SS2_LeaderTrait_Major_MakeshiftArmorer'; // Makeshift Armorer
            20: Result := 'SS2_LeaderTrait_Minor_ShakedownArtist'; // Shakedown
            21: Result := 'SS2_LeaderTrait_Weakness_RaiderAtHeart'; // Raider at Heart
            22: Result := 'SS2_LeaderTrait_Major_MeleeTrainer'; // Trainer
            23: Result := 'SS2_LeaderTrait_Weakness_Depressed'; // Depressed
            24: Result := 'SS2_LeaderTrait_Minor_FarmingExperience'; // Ex-Farmer
            25: Result := 'SS2_LeaderTrait_Minor_MilitaryMind'; // Military Mind
            26: Result := 'SS2_LeaderTrait_Weakness_SelfDoubt'; // Self Doubt
            27: Result := 'SS2_LeaderTrait_Major_Lifebringer'; // Lifebringer
            28: Result := 'SS2_LeaderTrait_Minor_Enthusiastic'; // Enthusiastic
            29: Result := 'SS2_LeaderTrait_Weakness_Naive'; // Naive
            30: Result := 'SS2_LeaderTrait_Minor_PartyAnimal'; // Party Animal
            31: Result := 'SS2_LeaderTrait_Minor_Mercenary'; // Mercenary
            32: Result := 'SS2_LeaderTrait_Major_OneMutantArmy'; // One Mutant Army
            33: Result := 'SS2_LeaderTrait_Minor_Defender'; // Defender
            34: Result := 'SS2_LeaderTrait_Weakness_HealthyAppetite'; // Healthy Appetite
            35: Result := 'SS2_LeaderTrait_Weakness_Synthetic'; // Synthetic
            36: Result := 'SS2_LeaderTrait_Minor_Entertainer'; // Entertainer
            37: Result := 'SS2_LeaderTrait_Weakness_Ghoulish'; // Ghoulish
            38: Result := 'SS2_LeaderTrait_Weakness_HealthyAppetite'; // Lonewolf
            39: Result := 'SS2_LeaderTrait_Major_Investigator'; // Investigator
            40: Result := 'SS2_LeaderTrait_Major_LogisticsExpert'; // Logistics Expert
            41: Result := 'SS2_LeaderTrait_Minor_Entrepreneur'; // Entrepreneur
            42: Result := 'SS2_LeaderTrait_Weakness_Communist'; // Communist
            43: Result := 'SS2_LeaderTrait_Weakness_Technophobe'; // Technophobic
            44: Result := 'SS2_LeaderTrait_Weakness_FunPolice'; // Fun Police
            45: Result := 'SS2_LeaderTrait_Minor_GoodNeighbor'; // Good Neighbor
            46: Result := 'SS2_LeaderTrait_Weakness_Taskmaster'; // Taskmaster
            47: Result := 'SS2_LeaderTrait_Minor_Caravaneer'; // Caravaneer
            48: Result := 'SS2_LeaderTrait_Minor_FriendOfSheng'; // Friend of Sheng
            49: Result := 'SS2_LeaderTrait_Weakness_Wasteful'; // Wasteful
            50: Result := 'SS2_LeaderTrait_Weakness_Embezzler'; // Embezzler
            51: Result := 'SS2_LeaderTrait_Weakness_Unimaginative'; // Unimaginative
            52: Result := 'SS2_LeaderTrait_Major_Engineer'; // Engineer
            53: Result := 'SS2_LeaderTrait_Minor_Promoter'; // Promoter
            54: Result := 'SS2_LeaderTrait_Minor_Optimizer'; // Optimizer
            55: Result := 'SS2_LeaderTrait_Weakness_Notorious'; // Notorious
            56: Result := 'SS2_LeaderTrait_Minor_Charismatic'; // Charismatic
            57: Result := 'SS2_LeaderTrait_Minor_Welcoming'; // Welcoming
            58: Result := 'SS2_LeaderTrait_Weakness_Allergies'; // Allergies
            59: Result := 'SS2_LeaderTrait_Major_MinutemenAlly'; // Minutemen Ally
            60: Result := 'SS2_LeaderTrait_Major_ChildrenOfAtomAlly'; // COA Ally
            61: Result := 'SS2_LeaderTrait_Major_MadScientist_OverseerBarstow'; // Mad Scientist
            62: Result := 'SS2_LeaderTrait_Major_RabbleRouser'; // Rabble Rouser
        end;
    end;

    function getSS2TraitMisc(oldId: integer): IInterface;
    var
        newEdid: string;
    begin
        Result := nil;

        //AddMessage('BLA '+getSS2TraitEdid(oldId));
        newEdid := getSS2TraitEdid(oldId);
        if(newEdid = '') then exit;

        // find the thing
        Result := FindObjectInFileByEdid(ss2masterFile, newEdid);
    end;

    procedure convertLeaderTraitArray(oldScript, newScript: IInterface; oldPropName, newPropName: string);
    var
        i: integer;
        oldProp, newProp: IInterface;
        oldId: integer;
        newTrait, newStruct: IInterface;
    begin
        oldProp := getScriptProp(oldScript, oldPropName);
        if(not assigned(oldProp)) then exit;

        clearScriptProperty(newScript, newPropName);
        newProp := getOrCreateScriptPropArrayOfStruct(newScript, newPropName);
        // AddMessage('yes assigned');
        // dumpElem(oldProp);
        for i:=0 to ElementCount(oldProp)-1 do begin
            oldId := StrToInt(GetEditValue(ElementByIndex(oldProp, i)));

            newTrait := getSS2TraitMisc(oldId);

            if(not assigned(newTrait)) then begin
                AddMessage('WARNING: Failed to convert Trait #'+IntToStr(oldID)+' for '+newPropName+'. It''s probably not supported in SS2 yet.');
                continue;
            end;

            newStruct := appendStructToProperty(newProp);
            setStructMember(newStruct, 'BaseForm', newTrait);
        end;

        // failsafe of sorts
        if(ElementCount(newProp) = 0) then begin
            deleteScriptProp(newScript, newPropName);
        end;
    end;

    procedure convertLeaderRequirements(edidBase: string; oldScript, newScript: IInterface);
    var
        oldReqs, newReqMisc, newReqScript: IInterface;
        newReqEdid: string;
        i: integer;
        curStruct, globalForm, newStruct, newReqProp: IInterface;
        globalVal: float;
    begin
        // // - Requirements > Requirements - was array of GlobalValueMap which was fValue + gGlobal, is now a UsageRequirements miscobject, which has an array of GlobalVariableSet which can replace fill that role
        oldReqs := getScriptProp(oldScript, 'Requirements');
        if(not assigned(oldReqs)) then exit;

        //newAllowedSettlements := getOrCreateScriptPropArrayOfStruct(newScript, 'LimitToSettlements');

        // SS2_LeaderCard_OverseerBarstow "Overseer Barstow" [WEAP:03021C8A]

        newReqEdid := generateEdid(leaderCardPrefix+'Req_', edidBase);
        newReqMisc := getCopyOfTemplate(targetFile, usageReqsTemplate, newReqEdid);

        setScriptProp(newScript, 'Requirements', newReqMisc);

        newReqScript := getScript(newReqMisc, 'SimSettlementsV2:MiscObjects:UsageRequirements');

        // newReqProp := getOrCreateScriptPropArrayOfStruct(newReqScript, 'GlobalRequirements');
        newReqProp := getOrCreateScriptPropArrayOfStruct(newReqScript, 'GlobalRequirements');
        clearProperty(newReqProp);

        for i:=0 to ElementCount(oldReqs)-1 do begin
            curStruct := ElementByIndex(oldReqs, i);

            // these are GlobalVariable based only
            globalForm := getStructMember(curStruct, 'gGlobal');
            globalVal  := getStructMember(curStruct, 'fValue');

            newStruct := appendStructToProperty(newReqProp);

            // put stuff in it
            // form: GlobalForm
            // val: fValue
            addRequiredMastersSilent(globalForm, targetFile);

            setStructMember(newStruct, 'GlobalForm', globalForm);
            setStructMember(newStruct, 'fValue', globalVal);

            // dumpElem(curStruct);
        end;

    end;

    function processLeaderCard(e: IInterface): boolean;
    var
        oldAllowedSettlements, curOldSettlement, oldScript, oldFlag, oldReqs, oldLeaderMsg, oldActorRecord: IInterface;
        oldActorFormId, oldFlagFormId, settlementFormId: cardinal;
        oldEdid, oldActorPluginName, oldFlagPluginName, oldFlagEdid: string;
        edidBase, newFlagEdid, settlementPluginName: string;
        newObj, newScript, newFlag, newReqs, newActorRecord: IInterface;
        newAllowedSettlements, newSettleStruct, newTraitMajor, newTraitMinor, newWeakness, newOmod: IInterface;
        i, oldTraitMajorIndex: integer;
        oldDesc: TStringList;
        newDescStr: string;
    begin
        // kgSIM_LeaderCard_OverseerBarstow "Overseer Barstow" [MISC:010105A2]
        Result := false;
        oldScript := getScript(e, 'SimSettlements:LeaderCard');
        if(not assigned(oldScript)) then exit;
        AddMessage('Processing '+FullPath(e));
        Result := true;
        sourceFile := GetFile(e);
        loadValidMastersFromFile(sourceFile);

        oldEdid := EditorID(e);

        // - FormID + PluginName becomes ActorBaseForm, this is a UniversalForm type that can have either the actual form, or the FormID + Plugin name
        oldActorFormId      := getScriptPropDefault(oldScript, 'formID', 0);
        oldActorPluginName  := getScriptPropDefault(oldScript, 'PluginName', '');

        if(oldActorFormId = 0) or (oldActorPluginName = '') then begin
            AddMessage(oldEdid+' is not a valid leader card. FormID and/or PluginName are missing.');
            exit;
        end;

        edidBase := stripPrefix('LeaderCard_', stripPrefix(oldFormPrefix, oldEdid));

        // generate the new thing
        newObj := getCopyOfTemplate(targetFile, leaderCardTemplate, generateEdid(leaderCardPrefix, edidBase));
        newScript := getScript(newObj, 'SimSettlementsV2:Weapons:LeaderCard');

        // trivial stuff
        SetElementEditValues(newObj, 'FULL', GetElementEditValues(e, 'FULL'));

        // easy stuff




        // - bCanNotLeadOutposts, bCanOnlyleadOutposts, bIgnoreCommandableFlag are identical
        setScriptProp(newScript, 'bCanNotLeadOutposts', getScriptPropDefault(oldScript, 'bCanNotLeadOutposts', false));
        setScriptProp(newScript, 'bCanOnlyleadOutposts', getScriptPropDefault(oldScript, 'bCanOnlyleadOutposts', false));
        setScriptProp(newScript, 'bIgnoreCommandableFlag', getScriptPropDefault(oldScript, 'bIgnoreCommandableFlag', false));

        // medium stuff

        // maybe convert the actor
        oldActorRecord := getFormByFilenameAndFormID(oldActorPluginName, oldActorFormId);
        if(assigned(oldActorRecord)) then begin
            // maybe convert
            if(isSameFile(GetFile(oldActorRecord), sourceFile)) then begin
                newActorRecord := translateForm(oldActorRecord);
                if(assigned(newActorRecord)) then begin
                    setUniversalForm(newScript, 'ActorBaseForm', newActorRecord);
                end else begin;
                    setUniversalForm(newScript, 'ActorBaseForm', oldActorRecord);
                end;
            end else begin
                setUniversalForm(newScript, 'ActorBaseForm', oldActorRecord);
            end;
        end else begin
            setUniversalForm_id(newScript, 'ActorBaseForm', oldActorFormId, oldActorPluginName);
        end;


        // - PreferredFlagFormID + PreferredFlagPlugin becomes PreferredFlag, this is a Univeral Form type that can have either the actual form or the FormID + Plugin name - should be pointing to a SS2_ThemeDefinition_Flags_ armor object.
        oldFlagFormId       := getScriptPropDefault(oldScript, 'PreferredFlagFormID', 0);
        oldFlagPluginName   := getScriptPropDefault(oldScript, 'PreferredFlag', '');

        // do we have that flag? did we convert that flag?
        // can we convert the flag?
        if(GetFileName(sourceFile) <> oldFlagPluginName) then begin
            AddMessage('WARNING: Flag for Leader Card '+oldEdid+' cannot be converted automatically.');
        end else begin
            oldFlag := getFormByFilenameAndFormID(oldFlagPluginName, oldFlagFormId);
            if(not assigned(oldFlag)) then begin
                AddMessage('WARNING: Flag for Leader Card '+oldEdid+' cannot be converted automatically.');
            end else begin
                // did we convert the flag?
                oldFlagEdid := EditorID(oldFlag);
                newFlagEdid := getSS2VersionEdid(oldFlagEdid);
                newFlag := getFormByFileAndFormID(targetFile, newFlagEdid);
                if(not assigned(newFlag)) then begin
                    newFlagEdid := GenerateEdid(flagPrefix, stripPrefix('DynamicFlag_', stripPrefix(oldFormPrefix, oldFlagEdid)));
                    newFlag := getFormByFileAndFormID(targetFile, newFlagEdid);

                    if(not assigned(newFlag)) then begin
                        // attempt to convert it
                        newFlag := processAndReturnFlag(oldFlag);

                        if(not assigned(newFlag)) then begin
                            AddMessage('WARNING: Flag for Leader Card '+oldEdid+' cannot be converted automatically.');
                        end else begin
                            setUniversalForm(newScript, 'PreferredFlag', newFlag);
                        end;
                    end;
                end;
            end;
        end;

        // convert the trait stuff
        // TEST
        // AddMessage('Old Major '+IntToStr(getScriptPropDefault(oldScript, 'MajorBenefit', -1)));
        //AddMessage('Old Minor '+IntToStr(getScriptPropDefault(oldScript, 'MinorBenefits', -1)));
        //AddMessage('Old Penal '+IntToStr(getScriptPropDefault(oldScript, 'Penalties', -1)));

        oldTraitMajorIndex := getScriptPropDefault(oldScript, 'MajorBenefit', -1);
        newTraitMajor := getSS2TraitMisc(oldTraitMajorIndex);
        convertLeaderTraitArray(oldScript, newScript, 'MinorBenefits', 'MinorTraits');
        convertLeaderTraitArray(oldScript, newScript, 'Penalties', 'Weaknesses');
        //newTraitMinor := getSS2TraitMisc(getScriptPropDefault(oldScript, 'MinorBenefits', -1));
        //newWeakness   := getSS2TraitMisc(getScriptPropDefault(oldScript, 'Penalties', -1));

        // MajorBenefit > MajorTrait
        // MinorBenefits > MinorTraits
        // Penalties > Weaknesses

        if(assigned(newTraitMajor)) then begin
            setScriptProp(newScript, 'MajorTrait', newTraitMajor);
        end else begin
            AddMessage('WARNING: Failed to convert MajorTrait #'+IntToStr(oldTraitMajorIndex)+'. It'' probably not supported in SS2 yet.');
        end;

        // hard stuff
        // - AllowedSettlements > LimitToSettlements - was array of ExternalForm type which was iFormID + sPlugin, is now array of UniversalForm
        oldAllowedSettlements := getScriptProp(oldScript, 'AllowedSettlements');
        if(assigned(oldAllowedSettlements)) then begin

            newAllowedSettlements := getOrCreateScriptPropArrayOfStruct(newScript, 'LimitToSettlements');

            for i:=0 to ElementCount(oldAllowedSettlements)-1 do begin
                curOldSettlement := ElementByIndex(oldAllowedSettlements, i);
                // struct containing iFormID and sPlugin
                settlementFormId    := getStructMemberDefault(curOldSettlement, 'iFormID', 0);
                settlementPluginName:= getStructMemberDefault(curOldSettlement, 'sPlugin', '');

                newSettleStruct := appendStructToProperty(newAllowedSettlements);

                setUniversalFormStruct_id(newSettleStruct, settlementFormId, settlementPluginName);
                // AddMessage('Something '+settlementPluginName);
            end;
        end;

        // extra hard stuff
        // - Requirements > Requirements - was array of GlobalValueMap which was fValue + gGlobal, is now a UsageRequirements miscobject, which has an array of GlobalVariableSet which can replace fill that role
        convertLeaderRequirements(edidBase, oldScript, newScript);

        // what it this even?


        // - LeaderSelectMessage - Take the DESC field make the first line the Name field of an Object Mod from template SS2_Template_LeaderCardDescription, and the remaining lines the DESC field of that same Object Mod, then set that object mod on the default template for the leader card.
        oldLeaderMsg := getScriptProp(oldScript, 'LeaderSelectMessage');
        //AddMessage('WHAT');
        if(assigned(oldLeaderMsg)) then begin
            // AddMessage('BLARGH');
            // GetElementEditValues(oldLeaderMsg, 'FULL');
            // make the first line the Name field of an Object Mod from template SS2_Template_LeaderCardDescription
            // the remaining lines the DESC field of that same Object Mod

            newOmod := getCopyOfTemplate(targetFile, SS2_Template_LeaderCardDescription, generateEdid(leaderCardPrefix+'DescOmod_', stripPrefix(leaderCardPrefix, edidBase)));

            oldDesc := TStringList.create;

            oldDesc.Delimiter := #13;//'\n somehow';
            oldDesc.StrictDelimiter := True; // Spaces excluded from being a delimiter
            oldDesc.DelimitedText := GetElementEditValues(oldLeaderMsg, 'DESC');
            newDescStr := '';


            for i:=0 to oldDesc.count-1 do begin
                // AddMessage('BLA '+oldDesc[i]);

                if(i = 0) then begin
                    // set name
                    SetElementEditValues(newOmod, 'FULL', oldDesc[i]);
                end else begin
                    newDescStr := newDescStr + #13#10 + trim(oldDesc[i]);
                    // newDescStr
                end;
            end;

            newDescStr := trim(newDescStr);
            SetElementEditValues(newOmod, 'DESC', newDescStr);

            oldDesc.free();

            // put that OMOD into the stuff
            generateTemplateCombination(newObj, newOmod);
        end;

        // finally, register the thing
        registerConvertedContent(newObj, SS2_FLID_LeaderCards);

    end;

    function processFoundation(e: IInterface): boolean;
    var
        oldScript, oldSpawnedForm, oldTfScript, oldMatswap, oldBlock, oldCobj, oldObnd, oldObndEntry, oldPositionOffsets: IInterface;
        newMatswap, newObject, newCobj, newMisc, newMiscScript, newObnd, spawnDataStruct, contentKeyword: IInterface;
        oldOffsetX, oldOffsetY, oldOffsetZ, curBoundVal, posOffsetX, posOffsetY, posOffsetZ: float;
        i, tfType: integer;
        oldName, oldUserTag, edidBase, oldEdid, curKey: string;
    begin
        Result := false;

        // old script: SimSettlements:SpawnableFoundation
        oldScript := getScript(e, 'SimSettlements:SpawnableFoundation');
        if(not assigned(oldScript)) then exit;
        AddMessage('Processing '+FullPath(e));
        Result := true;
        sourceFile := GetFile(e);
        loadValidMastersFromFile(sourceFile);
        oldSpawnedForm := getScriptProp(oldScript, 'FoundationForm');
        oldTfScript := getScript(oldSpawnedForm, 'SimSettlements:TerraformBlock');

        oldEdid := EditorID(e);
        edidBase := stripPrefix('SpawnableFoundation_', stripPrefix(oldFormPrefix, oldEdid));

        tfType := findOldFoundationType(e);
        if(tfType = 0) then begin
            AddMessage('Foundation '+FullPath(e)+' cannot be converted, because it''s type cannot be determined.');
            exit;
        end;

        oldName := GetElementEditValues(e, 'FULL');
        oldUserTag := extactUserTagFromName(oldName);
        if(oldUserTag <> '') then begin
            oldName := trim(stripPrefix(oldUserTag, oldName));
        end;

        if(assigned(oldTfScript)) then begin
            // this is a terraformer
            // for simplicity's sake, only consider 2 without offset
            if(tfType <> 2) then begin
                AddMessage('Skipping terraformer '+EditorID(e)+', waiting for non-offset 2x2');
                exit;
            end;

            edidBase := StringReplace(edidBase, '2x2', '', [rfReplaceAll]);

            oldName := StringReplace(oldName, '1x1', '', [rfReplaceAll]);
            oldName := StringReplace(oldName, '2x2', '', [rfReplaceAll]);
            oldName := StringReplace(oldName, '3x3', '', [rfReplaceAll]);
            oldName := StringReplace(oldName, 'Terraformer', '', [rfReplaceAll]);
            oldName := StringReplace(oldName, ' - ', '', [rfReplaceAll]);
            oldName := regexReplace(oldName, '  +', ' ');
            oldName := trim(oldName);

            oldMatswap := PathLinksTo(oldSpawnedForm, 'Model\MODS');
            newMatswap := nil;
            if(assigned(oldMatswap)) then begin
                newMatswap := translateForm(oldMatswap);
            end;

            AddMessage('Generating terraformers for '''+oldName+''', matswap '+EditorID(newMatswap));
            // procedure generateTerraformers(tfName: string; edidBase: string; targetFile: IInterface; matSwap: IInterface);
            generateTerraformers(oldName, oldUserTag, edidBase, targetFile, newMatswap);
            exit;
        end;

        // otherwise, this is a regular foundation, and actually has to be translated
        if (tfType = -2) then begin
            AddMessage('Skipping terraformer '+EditorID(e)+', the non-offset version will be translated');
            exit;
        end;




        oldCobj := getObjectCobj(oldSpawnedForm);
        // I need:
        //  - the new block
        //  - the new COBJ
        //  - the new MISC
        newObject := translateForm(oldSpawnedForm);
        newCobj := createFoundationCobj(edidBase, newObject, oldCobj);
        newMisc := getCopyOfTemplate(targetFile, foundationTemplate, generateEdid(foundationPrefix, edidBase));

        // setup the new misc
        newMiscScript := getScript(newMisc, 'SimSettlementsV2:MiscObjects:Foundation');

        if(oldUserTag <> '') then begin
            setElementEditValues(newMisc, 'FULL', oldUserTag+' '+oldName);
        end else begin;
            setElementEditValues(newMisc, 'FULL', oldName);
        end;

        spawnDataStruct := getOrCreateScriptPropStruct(newMiscScript, 'SpawnData');
        setStructMember(spawnDataStruct, 'ObjectForm', newObject);
        // setScriptProp(newMiscScript, 'SpawnData', newObject);

        setPathLinksTo(newMisc, 'PTRN', pathLinksTo(newObject, 'PTRN'));

        applyModel(newObject, newMisc);

        // bounds, too?
        oldObnd := ElementByPath(e, 'OBND');
        newObnd := ElementByPath(newMisc, 'OBND');

        for i:=0 to ElementCount(oldObnd)-1 do begin
            oldObndEntry := ElementByIndex(oldObnd, i);
            curKey := DisplayName(oldObndEntry);
            curBoundVal := GetElementEditValues(oldObndEntry, curKey);

            SetElementEditValues(newObnd, curKey, curBoundVal);
        end;

        // position offsets
        oldPositionOffsets := getScriptProp(oldScript, 'PositionOffsets');
        posOffsetX := getValueFromPropertyDefault(oldPositionOffsets, 0, 0.0);
        posOffsetY := getValueFromPropertyDefault(oldPositionOffsets, 1, 0.0);
        posOffsetZ := getValueFromPropertyDefault(oldPositionOffsets, 2, 0.0);

        // these must be adjusted depending on the size. also do the register KW while we are at it
        case tfType of
            1:  begin
                    posOffsetZ := posOffsetZ + 10.0;
                    contentKeyword := SS2_FLID_1x1_Foundations;
                end;
            2:  begin
                    posOffsetZ := posOffsetZ + 10.0;
                    contentKeyword := SS2_FLID_2x2_Foundations;
                end;
            3:  begin
                    // no offsets here
                    contentKeyword := SS2_FLID_3x3_Foundations;
                end;
        end;

        if(posOffsetX <> 0.0) then setStructMember(spawnDataStruct, 'fPosX', posOffsetX);
        if(posOffsetY <> 0.0) then setStructMember(spawnDataStruct, 'fPosY', posOffsetY);
        if(posOffsetZ <> 0.0) then setStructMember(spawnDataStruct, 'fPosZ', posOffsetZ);


// praSim_Terraformer_Glowing_Sea_Rubble1x1_Spawnable "[PRA] 1x1 - Glowing Sea Rubble Terraformer" [MISC:04097ABF]
// SS2_PlotFoundation_1x1_Terraformer_Dirt "Dirt Terraformer" [MISC:03014C46]



        // for terraformers, regard the non-offset 2x2 only
        // for non-terraformers, convert 1x1 and 3x3 as usual, but only non-offset 2x2

        // is this a terraformer?


        // properties:
        // - FoundationForm  (object
        // - PositionOffsets (array of float)

        // new script is SimSettlementsV2:MiscObjects:Foundation
        // finally, register the thing
        registerConvertedContent(newMisc, contentKeyword);

        Result := true;
    end;

    function makeFlagMatswap(edidBase, origMat, suffix: string; sourceMatswap: IInterface): IInterface;
    var
        curOrigMat, curReplaceMat, newEdid: string;
        i: integer;
        subs, curSub, newSubs, newSub: IInterface;
    begin
        newEdid := GenerateEdid(flagPrefix, edidBase + '_MWSP_' + suffix);
        Result := nil;

        subs := ElementByPath(sourceMatswap, 'Material Substitutions');

        for i:=0 to ElementCount(subs)-1 do begin
            curSub := ElementByIndex(subs, i);
            curOrigMat := GetElementEditValues(curSub, 'BNAM');
            if(LowerCase(curOrigMat) = 'setdressing\clothflag01alpha.bgsm') then break;
            // curReplaceMat := GetElementEditValues(curSub, 'SNAM');
            // SetDressing\clothflag01alpha.bgsm
            // lastSub :=
        end;

        if(not assigned(curSub)) then exit; // shouldn't actually happen

        curReplaceMat := GetElementEditValues(curSub, 'SNAM');

        Result := getCopyOfTemplate(targetFile, flagTemplate_Matswap, newEdid);
        // the template should have one substitution exactly
        newSubs := ElementByPath(Result, 'Material Substitutions');
        newSub := ElementByIndex(newSubs, 0);

        setElementEditValues(newSub, 'BNAM', origMat);
        setElementEditValues(newSub, 'SNAM', curReplaceMat);
    end;

    function processAndReturnFlag(e: IInterface): IInterface;
    var
        oldScript, oldFlagDown, oldFlagUp, oldFlagWall: IInterface;
        newElem, newScript, newFlagDown, newFlagWaving, newFlagWall, newMatswap, newMatswapSource: IInterface;
        newFlagBanner, newFlagBannerTorn, newFlagBannerTornWaving, newFlagCircle01, newFlagCircle02: IInterface;
        newMatswapBanner, newMatswapCircle: IInterface;
        oldEdid, newEdid, flagName, edidBase: string;
        remapIndex: float;
    begin
        Result := nil;
        // old stuff
        // example: kgSIM_DynamicFlag_USA "American Flag" [MISC:010164AF]
        // script: SimSettlements:DynamicFlag
        oldScript := GetScript(e, 'SimSettlements:DynamicFlag');
        if(not assigned(oldScript)) then exit;

        AddMessage('Processing Flag: '+EditorID(e));
        // props:
        // - FlagDown
        // - FlagUp: waving MSTT flag
        // - FlagWall
        oldFlagDown := getScriptProp(oldScript, 'FlagDown');
        oldFlagUp := getScriptProp(oldScript, 'FlagUp');
        oldFlagWall := getScriptProp(oldScript, 'FlagWall');

        flagName := GetElementEditValues(e, 'FULL');
        // AddMessage('Flag name: '+flagName);
        oldEdid := EditorID(e);

        if (not assigned(oldFlagDown)) then begin
            AddMessage('ERROR: '+Name(e)+' is invalid: No FlagDown');
            exit;
        end;

        if (not assigned(oldFlagUp)) then begin
            AddMessage('ERROR: '+Name(e)+' is invalid: No FlagUp');
            exit;
        end;

        if (not assigned(oldFlagWall)) then begin
            AddMessage('ERROR: '+Name(e)+' is invalid: No FlagWall');
            exit;
        end;
        // applyModelMatswap

        sourceFile := GetFile(e);
        loadValidMastersFromFile(sourceFile);

        edidBase := stripPrefix('DynamicFlag_', stripPrefix(oldFormPrefix, oldEdid));

        newEdid := GenerateEdid(flagPrefix, edidBase);
        // Flags seem to be ARMOs
        // SS2_ThemeDefinition_Flags_American "American" [ARMO:0301BB4B]
        // template: SS2_ThemeDefinition_Flags_Template "Flag Name Here" [ARMO:030201A1]
        newElem := getCopyOfTemplate(targetFile, flagTemplate, newEdid);
        Result := newElem;

        SetElementEditValues(newElem, 'FULL', flagName);

        newScript := getScript(newElem, 'SimSettlementsV2:Armors:ThemeDefinition_Flags');

        newFlagDown   := translateForm(oldFlagDown);
        newFlagWaving := translateForm(oldFlagUp);
        newFlagWall   := translateForm(oldFlagWall);

        SetElementEditValues(newFlagDown, 'EDID', GenerateEdid('FlagDown_', edidBase));
        SetElementEditValues(newFlagWaving, 'EDID', GenerateEdid('FlagWaving_', edidBase));
        SetElementEditValues(newFlagWall, 'EDID', GenerateEdid('FlagWall_', edidBase));

        newMatswap := pathLinksTo(newFlagDown, 'Model\MODS');
        newMatswapSource := newFlagDown;

        applyModel(newFlagWall, newElem);

        if(not assigned(newMatswap)) then begin
            newMatswap := pathLinksTo(newFlagWaving, 'Model\MODS');
            newMatswapSource := newFlagWaving;
            if(not assigned(newMatswap)) then begin
                newMatswap := pathLinksTo(newFlagWall, 'Model\MODS');
                newMatswapSource := newFlagWall;
                if(not assigned(newMatswap)) then begin
                    newMatswapSource := nil;
                    AddMessage('WARNING: Found no matswap for flag '+Name(newElem)+', this requires manual fixing.');
                end;
            end;
        end;




        // needed records:
        // - FlagBannerTownStatic: SS2_StaticBanner_USA [STAT:0301BB5E], NEW, rectangular narrow vertical banner
        // - FlagBannerTownTorn: SS2_StaticBannerTorn_USA [STAT:0301BB60], NEW, as above, but torn
        // - FlagBannerTownTornWaving: SS2_WavingBannerTorn_USA_DoNotSCOL [STAT:0301BB62], NEW, similar yet again, maybe animated
        // - FlagHalfCircleFlag01: SS2_HalfCircleFlag01_USA [STAT:0301BB54], NEW, semicircular flag hanging from 2 points
        // - FlagHalfCircleFlag02: SS2_HalfCircleFlag02_USA [STAT:0301BB55], NEW, semicircular flag hanging from 3 points

        // - FlagDown: SS2_FlagDown_USA [STAT:03012BF3], same as old FlagDown
        // - FlagWall: SS2_FlagWallUSA "U.S. Flag" [STAT:03014DE7], same as old FlagWall
        // - FlagWaving: SS2_FlagWavingUSA01 [MSTT:03017ABD], same as old FlagUp

        // Matswap: SS2_MS_Banner_USAToRR [MSWP:0201BB81]
        // - Original: SS2\SetDressing\USFlagNoAlphaOneSided.BGSM
        //
        newFlagBanner           := getCopyOfTemplate(targetFile, flagTemplate_Banner, GenerateEdid('FlagBanner_', edidBase));
        newFlagBannerTorn       := getCopyOfTemplate(targetFile, flagTemplate_BannerTorn, GenerateEdid('FlagBannerTorn_', edidBase));
        newFlagBannerTornWaving := getCopyOfTemplate(targetFile, flagTemplate_BannerTornWaving, GenerateEdid('FlagBannerTornWaving_', edidBase));

        // Matswap: SS2_MS_HalfCircle_USAToRR [MSWP:0201BB7E]
        // - Original: setdressing\HalfCircleFlag01.BGSM
        newFlagCircle01         := getCopyOfTemplate(targetFile, flagTemplate_Circle01, GenerateEdid('FlagHalfCircle01_', edidBase));
        newFlagCircle02         := getCopyOfTemplate(targetFile, flagTemplate_Circle02, GenerateEdid('FlagHalfCircle02_', edidBase));
        if(assigned(newMatswapSource)) then begin
            // makeFlagMatswap // newMatswapBanner, newMatswapCircle: IInterface;

            newMatswapBanner := makeFlagMatswap(edidBase, 'SS2\SetDressing\USFlagNoAlphaOneSided.BGSM', 'banner', newMatswap);
            newMatswapCircle := makeFlagMatswap(edidBase, 'setdressing\HalfCircleFlag01.BGSM', 'halfcircle', newMatswap);

            // dumpElem(newMatswapBanner);

            // applyModelMatswap(newMatswapSource, newElem);

            applyMatswapToModel(newMatswapBanner, -1, newFlagBanner);
            applyMatswapToModel(newMatswapBanner, -1, newFlagBannerTorn);
            applyMatswapToModel(newMatswapBanner, -1, newFlagBannerTornWaving);

            applyMatswapToModel(newMatswapCircle, -1, newFlagCircle01);
            applyMatswapToModel(newMatswapCircle, -1, newFlagCircle02);
        end;

        // set props
        setScriptProp(newScript, 'FlagWall', newFlagWall);
        setScriptProp(newScript, 'FlagDown', newFlagDown);
        setScriptProp(newScript, 'FlagWaving', newFlagWaving);

        setScriptProp(newScript, 'FlagBannerTownStatic', newFlagBanner);
        setScriptProp(newScript, 'FlagBannerTownTorn', newFlagBannerTorn);
        setScriptProp(newScript, 'FlagBannerTownTornWaving', newFlagBannerTornWaving);
        setScriptProp(newScript, 'FlagHalfCircleFlag01', newFlagCircle01);
        setScriptProp(newScript, 'FlagHalfCircleFlag02', newFlagCircle02);

        // registered using SS2_FLID_ThemeDefinitions_Flags [KYWD:0301BB6E]

        registerConvertedContent(newElem, SS2_FLID_ThemeDefinitions_Flags);
    end;

    function processFlag(e: IInterface): boolean;
    var
        newFlag: IInterface;
    begin
        newFlag := processAndReturnFlag(e);

        Result := assigned(newFlag);
    end;


    // Called before processing
    // You can remove it if script doesn't require initialization code
    function Initialize: integer;
    var
        f4esm: IInterface;
        miscGroup, kywdGroup: IInterface;
    begin
		plotMapping := nil;

        //f4esm := FileByName('Fallout4.esm');
        //targetFile := showFileSelectionDialog();
        if(not showInitialConfigDialog()) then begin
            AddMessage('Cancelled');
            Result := 1;
            exit;
        end;

        if(not initSS2Lib()) then begin
            AddMessage('initSS2Lib failed!');
            Result := 1;
            exit;
        end;

        loadRecycledMiscs(targetFile, true);

        globalNewFormPrefix := newFormPrefix;

        //AddMasterIfMissing(targetFile, 'Fallout4.esm');
        miscGroup := GroupBySignature(ss2masterFile, 'MISC');
        kywdGroup := GroupBySignature(ss2masterFile, 'KYWD');

        formMappingCache := TStringList.create;
        skinBacklog := TList.Create;

        typeFormlistCache := TJsonObject.create;

        signatureBlacklist := TStringList.create;
        // add signatures to skip here
        // KSIZ is the number of keywords, it will be updated automatically
        signatureBlacklist.add('KSIZ');


        commercialExteriorQuestProperties := TStringList.create;
        commercialExteriorQuestProperties.add('MyArmorStoreSizeABuildingPlans');
        commercialExteriorQuestProperties.add('MyBarSizeABuildingPlans');
        commercialExteriorQuestProperties.add('MyClinicSizeABuildingPlans');
        commercialExteriorQuestProperties.add('MyClothingStoreSizeABuildingPlans');
        commercialExteriorQuestProperties.add('MyGeneralStoreSizeABuildingPlans');
        commercialExteriorQuestProperties.add('MyWeaponStoreSizeABuildingPlans');
        commercialExteriorQuestProperties.add('MyPowerArmorStoreSizeABuildingPlans');
        commercialExteriorQuestProperties.add('MyBeautyStoreSizeABuildingPlans');
        commercialExteriorQuestProperties.add('MyFurnitureStoreSizeABuildingPlans');
        commercialExteriorQuestProperties.add('MyOtherCommercialSizeABuildingPlans');

        commercialInteriorQuestProperties := TStringList.create;
        commercialInteriorQuestProperties.add('MyArmorStoreInteriorBuildingPlans');
        commercialInteriorQuestProperties.add('MyBarInteriorBuildingPlans');
        commercialInteriorQuestProperties.add('MyClinicInteriorBuildingPlans');
        commercialInteriorQuestProperties.add('MyClothingStoreInteriorBuildingPlans');
        commercialInteriorQuestProperties.add('MyGeneralStoreInteriorBuildingPlans');
        commercialInteriorQuestProperties.add('MyWeaponStoreInteriorBuildingPlans');
        commercialInteriorQuestProperties.add('MyPowerArmorStoreInteriorBuildingPlans');
        commercialInteriorQuestProperties.add('MyBeautyStoreInteriorBuildingPlans');
        commercialInteriorQuestProperties.add('MyFurnitureStoreInteriorBuildingPlans');
        commercialInteriorQuestProperties.add('MyOtherCommercialInteriorBuildingPlans');

        Result := 0;
    end;



    function Process(e: IInterface): integer;

    begin
        Result := 0;

        if(Signature(e) = 'MISC') then begin
            if(processBuildingPlan(e)) then begin
                exit;
            end;

            // try something other
            if(assigned(getScript(e, 'SimSettlements:SimBuildingPlanSkin'))) then begin
                AddMessage('Adding skin '+DisplayName(e)+' to backlog');
                skinBacklog.add(TObject(e));
                exit;
            end;

            if(processFurniture(e)) then begin
                exit;
            end;

            if(processFlag(e)) then begin
                exit;
            end;

            if(processFoundation(e)) then begin
                exit;
            end;

            if(processLeaderCard(e)) then begin
                exit;
            end;

        end;


        if(processDesk(e)) then exit;

    end;

    function getPlotMappingData(): TJsonObject;
	var
		csvLines, csvCols: TStringList;
		i: integer;
		curLine, search, replace: string;
		replacePlot, plotScript: IInterface;
	begin
        Result := TJsonObject.create;
		if(not FileExists(plotMappingFile)) then begin
			exit;
		end;


		plotMapping := TStringList.create;
		plotMapping.CaseSensitive := false;
		plotMapping.Duplicates := dupIgnore;

		AddMessage('Loading plot mapping from '+plotMappingFile);

		csvLines := TStringList.create;
		csvLines.LoadFromFile(plotMappingFile);
		for i:=0 to csvLines.count-1 do begin
			curLine := trim(csvLines.Strings[i]);
			if(curLine = '') then begin
				continue;
			end;

			csvCols := TStringList.create;

			csvCols.Delimiter := ',';
			csvCols.StrictDelimiter := TRUE;
			csvCols.DelimitedText := curLine;

			if (csvCols.count >= 2) then begin
				search  := trim(csvCols.Strings[0]);
				replace := trim(csvCols.Strings[1]);

				if(search <> '') and (replace <>'') then begin
					Result.S[search]:= replace;
				end;
			end;

			csvCols.free();
        end;

		csvLines.free();
	end;

    procedure writePlotMapping();
    var
        i: integer;
        oldEdid, newEdid: string;
        newPlot: IInterface;
        list: TStringList;
        curData: TJsonObject;
    begin
        if(formMappingCache.count = 0) then exit;
        curData := getPlotMappingData();

        for i:=0 to formMappingCache.count-1 do begin
            oldEdid := formMappingCache[i];
            newPlot := ObjectToElement(formMappingCache.Objects[i]);
            newEdid := EditorID(newPlot);

            curData.S[oldEdid] := newEdid;
        end;


        list := TStringList.create();
        for i:=0 to curData.count -1 do begin
            oldEdid := curData.Names[i];
            list.add(oldEdid+','+curData.S[oldEdid]);
        end;

        list.SaveToFile(plotMappingFile);


        list.free();
        curData.free();
    end;

    // Called after processing
    // You can remove it if script doesn't require finalization code
    function Finalize: integer;
    var
        i : integer;
        curSkin: IInterface;
    begin
        for i:=0 to skinBacklog.count-1 do begin
            curSkin := ObjectToElement(skinBacklog[i]);
            AddMessage('From backlog, got '+displayName(curSkin));
            processBuildingPlanSkin(curSkin);
        end;

        if(assigned(targetFile)) then begin
            // clean masters
            AddMessage('Cleaning masters of '+GetFileName(targetFile));
            CleanMasters(targetFile);
        end;

        writePlotMapping();

		Result := 0;

		if(nil <> plotMapping) then begin
			plotMapping.free();
		end;
        typeFormlistCache.free();
        skinBacklog.free();
        formMappingCache.free();
        cleanupSS2Lib();
    end;

end.