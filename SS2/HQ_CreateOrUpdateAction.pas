{
    Run on Room Config to update. Run on anything else to generate a new
    Last Update: 2025-09-23
}
unit ImportHqRoom;
	uses 'SS2\SS2Lib'; // uses praUtil
	uses 'SS2\CobbLibrary';
	uses 'SS2\PexParser';

	const
		cacheFile = ScriptsPath + 'SS2\HqRoomCache.json';
        cacheFileVersion = 9;
		fakeClipboardFile = ScriptsPath + 'SS2\HqRoomClipboard.txt';

		progressBarChar = '|';
		progressBarLength = 70;
		RESOURCE_COMPLEXITY_FULL = 3;
		RESOURCE_COMPLEXITY_CATEGORY = 2;
		RESOURCE_COMPLEXITY_MINIMAL = 1;
	var
		targetFile: IInterface;
		targetElem: IInterface;
		targetHQ: IInterface;
		// lists
		listHQRefs: TStringList;
		//listHqManagers: TStringList;
		listRoomShapes: TStringList;
		listKeywordsConstruct, listKeywordsUpgrade, listKeywordsTech: TStringList;
		listDepartmentObjects: TStringList;
		listActionGroups: TStringList;
		listRoomConfigs: TStringList;
		listRoomFuncs: TStringList;
		listModels: TStringList;
		listModelsMisc: TStringList;
		listRoomResources: TStringList;
		listTechActionTypes: TStringList;
        listPutDownSounds: TStringList;//SS2_SFX_HQProjectType
		// other lists
		edidLookupCache: TStringList;

		resourceLookupTable: TJsonObject;
		// general stuff needed from master
		SS2_HQ_FauxWorkshop: IInterface;
		SS2_FLID_HQActions: IInterface;
		SS2_HQ_WorkshopRef_GNN: IInterface;
		WorkshopItemKeyword: IInterface;
		SS2_TF_HologramGNNWorkshopTiny: IInterface;
		SS2_VirtualResourceCategory_Scrap: IInterface;
		SS2_VirtualResourceCategory_Supplies: IInterface;
		SS2_VirtualResourceCategory_RareMaterials: IInterface;
		SS2_VirtualResourceCategory_OrganicMaterials: IInterface;
		SS2_VirtualResourceCategory_MachineParts: IInterface;
		SS2_VirtualResourceCategory_BuildingMaterials: IInterface;
		SS2_VirtualResource_SuppliesCategory_Ammo: IInterface;
		SS2_VirtualResource_SuppliesCategory_Armor: IInterface;
		SS2_VirtualResource_SuppliesCategory_Chems: IInterface;
		SS2_VirtualResource_SuppliesCategory_WeaponParts: IInterface;
        SS2_UsageRequirements_PerformanceSettingOn_Clutter: IInterface;
		SS2_c_HQ_DailyLimiter_Scrap: IInterface;
		SS2_c_HQ_DailyLimiter_Supplies: IInterface;
        SS2_Tag_HQ_RoomIsClean: IInterface;
        SS2_Tag_HQ_ActionType_RoomConstruction: IInterface;
        SS2_Tag_HQ_ActionType_RoomUpgrade: IInterface;
        defaultUpgradeKw, defaultConstructionKw: IInterface;
        SS2_SFX_HQProjectType_Administration_Decorate,
        SS2_WorkshopMenu_HQ_Administration_Decorate : IInterface;
        // SS2_WorkshopMenu_HQ_Engineering_Upgrades_Other
        // SS2_WorkshopMenu_HQ_Facilities_Construction_Other
		// templates
		SS2_HQ_Action_RoomUpgrade_Template: IInterface;
		SS2_HQRoomLayout_Template: IInterface;
		CobjRoomUpgrade_Template: IInterface;
		CobjRoomConstruction_Template: IInterface;
		SS2_HQGNN_Action_AssignRoomConfig_Template: IInterface;
		SS2_HQ_RoomSlot_Template_GNN: IInterface;
		SS2_HQ_RoomSlot_Template: IInterface;
		SS2_HQBuildableAction_Template: IInterface;


		// progress bar stuff
		progressBarWindow: TForm;
		progressBarStack: TJsonArray;

		// other stuff
		hasFindObjectError: boolean;
		hasRelativeCoordinateLayout: boolean;
		hasNonRelativeCoordinateLayout: boolean;
		currentListOfUpgradeSlots: TStringList;

		currentCacheFile: TJsonObject;

        // hacks because xedit sux
        currentOpenMenu: TPopupMenu;
        currentUpgradeDescriptionData: TJsonObject;

        currentUpgradeDialog: TForm;


    function getFakeClipboardText(): string;
    var
        helper: TStringList;
    begin
        if(not FileExists(fakeClipboardFile)) then begin
            Result := '';
            exit;
        end;

        helper := TStringList.create();
        helper.loadFromFile(fakeClipboardFile);

        Result := concatLines(helper);

        helper.free();
    end;

    procedure setFakeClipboardText(str: string);
    var
        helper: TStringList;
    begin
        helper := TStringList.create();

        helper.add(str);

        helper.saveToFile(fakeClipboardFile);

        helper.free();
    end;

	procedure showProgressWindow();
	var
		textLabel, textBar: TLabel;
	begin
		if(nil <> progressBarWindow) then begin
			exit;
		end

		progressBarWindow := CreateDialog('Import HQ Room', 320, 100);


		textLabel := CreateLabel(progressBarWindow, 10, 10, '');
		textLabel.Name := 'textLabel';

		textBar := CreateLabel(progressBarWindow, 16, 32, '');
		textBar.Name := 'textBar';
		textBar.width := 290;

		progressBarWindow.show();
	end;

	procedure endProgress();
	begin
        if(progressBarStack.count = 0) then begin
            AddMessage('CRITICAL ERROR: ended progress more often than started it. This is a bug!');
        end;
		progressBarStack.delete(progressBarStack.count-1);

		if(progressBarStack.count = 0) then begin
			if(progressBarWindow <> nil) then begin
				progressBarWindow.close();
				progressBarWindow.free();
				progressBarWindow := nil;
			end;
		end;
	end;

	procedure startProgress(text: string; max: integer);
	var
		textLabel, textBar: TLabel;
		prevProgressData, thisProgressData: TJsonObject;
	begin

		if(progressBarWindow = nil) then begin
			showProgressWindow();
		end;

		prevProgressData := nil;
		if(progressBarStack.count > 0) then begin
			prevProgressData := progressBarStack.O[progressBarStack.count-1];
		end;

		thisProgressData := progressBarStack.addObject();
		// the maximal value
		thisProgressData.I['max'] := max;
		// nr of chars corresponding to the "full" bar
		thisProgressData.F['size'] := progressBarLength;
		// current progress
		thisProgressData.I['pos'] := 0;
		// special stuff
		if(max = 0) then begin
			thisProgressData.F['size'] := 0; // always 0
		end else begin
			if(prevProgressData <> nil) then begin
				thisProgressData.F['size'] := prevProgressData.F['size'] / prevProgressData.F['max'];
			end;
		end;

		if(text <> '') then begin
			textLabel := TLabel(progressBarWindow.FindComponent('textLabel'));
			textLabel.Caption := text;
		end;

		textBar := TLabel(progressBarWindow.FindComponent('textBar'));
		textBar.Caption := '';
		//progressBarMax := max;
	end;

	procedure updateProgress(cur: integer);
	var
		textBar: TLabel;
		i, newNr : integer;
		progressData: TJsonObject;
		newText: string;
	begin

		if(progressBarWindow = nil) then begin
			exit;
		end;

		if(not progressBarWindow.visible) then begin
			progressBarWindow.show();
		end;

		newNr := 0;

		// try doing it differently
		for i:=0 to progressBarStack.count-1 do begin
			progressData := progressBarStack.O[i];

			//AddMessage('checking stack '+progressData.toString());

			if(progressData.I['max'] > 0) then begin
				if(i < progressBarStack.count-1) then begin
					newNr := newNr + Round((progressData.I['cur'] / progressData.I['max']) * progressData.F['size']);
				end else begin
					newNr := newNr + Round(((cur) / progressData.I['max']) * progressData.F['size']);
					progressData.I['cur']  := cur;
				end;
			end;

		end;


		textBar := TLabel(progressBarWindow.FindComponent('textBar'));
		newText := StringRepeat(progressBarChar, newNr);
		if(textBar.Caption <> newText) then begin
			textBar.Caption := newText;

			progressBarWindow.Refresh();
		end;

	end;

	procedure removePrefixFromList(prefix: string; list: TStringList);
	var
		i, start, strlen: integer;

	begin
		strlen := length(prefix);
		for i:=0 to list.count-1 do begin
			start := pos(prefix, list[i]);
			if(start = 0) then begin

			end;
		end;
	end;

	procedure addObjectDupIgnore(list: TStringList; str: string; elem: IInterface);
	var
		i: integer;
	begin
		if(list.indexOf(str) >= 0) then begin
            // AddObject('addObjectDupIgnore('+str+'): skipping');
			exit;
		end;

		list.addObject(str, WinningOverrideOrSelf(elem));
	end;

	procedure loadModels();
	var
		containers, assets, relevantContainers: TStringList;
		i, j: integer;
		curRes, curFileName: string;
	begin
		AddMessage('Loading models (this will take a long time, but hopefully only necessary once)');

		containers := TStringList.create();
		relevantContainers := TStringList.create();
		ResourceContainerList(containers);

		for i:=0 to containers.count-1 do begin
			if(containers[i] = '') then begin
				// add loose files
				relevantContainers.add(containers[i]);
			end else begin
				curFileName := ExtractFileName(containers[i]);
				if(strEndsWithCI(curFileName, ' - Textures.ba2')) then begin
					continue;
				end;

				if(strStartsWithCI(curFileName, 'Fallout4 - ')) then begin
					continue;
				end;

				if ((LowerCase(curFileName) = 'ss2 - main.ba2') or strStartsWithCI(curFileName, 'SS2_XPAC')) then begin
					relevantContainers.add(containers[i]);
				end;

			end;
		end;
		containers.free();


		startProgress('Loading models...', relevantContainers.count);
		for i:=0 to relevantContainers.count-1 do begin
			assets := TStringList.create();

			ResourceList(relevantContainers[i], assets);
			AddMessage('Looking for models in '+relevantContainers[i]+', checking '+IntToStr(assets.count)+' assets');
			startProgress('', assets.count);
			for j:=0 to assets.count-1 do begin
				curRes := assets[j];

				if(strStartsWithCI(curRes, 'Meshes\AutoBuildPlots\Markers\Visible\Animation\')) then begin
					if(listModels.indexOf(curRes) < 0) then begin
						listModels.add(regexReplace(curRes, '^Meshes\\AutoBuildPlots\\Markers\\Visible\\Animation\\', ''));
					end;
				end else if(strStartsWithCI(curRes, 'Meshes\SS2C2\Interface\GNNRoomShapes')) then begin
					if(listModelsMisc.indexOf(curRes) < 0) then begin
						listModelsMisc.add(regexReplace(curRes, '^Meshes\\SS2C2\\Interface\\GNNRoomShapes\\', ''));
					end;
				end;
				updateProgress(j);
			end;
			endProgress();

			updateProgress(i);

			assets.free();
		end;

		endProgress();


		relevantContainers.free();

	end;

	function getResourceAvName(av: IInterface): string;
	var
		edid: string;
		regex: TPerlRegEx;
	begin
		edid := EditorID(av);
		if(edid = 'SS2_VirtualResource_Caps') then begin
			Result := 'Caps';
			exit;
		end;

		Result := edid;
		regex := TPerlRegEx.Create();

		try
			if(strStartsWith(edid, 'SS2_VirtualResource_Supplies_')) then begin
				regex.RegEx := '^SS2_VirtualResource_Supplies_([^_]+)_([^_]+)$';
			end else begin
				regex.RegEx := '^SS2_VirtualResource_([^_]+)_([^_]+)$';
			end;

            regex.Subject := edid;

            if (regex.Match()) then begin
				if(regex.GroupCount >= 2) then begin
					Result := regex.Groups[2] + ' (' + regex.Groups[1] + ')';
				end;
                // misnomer, is actually the highest valid index of regex.Groups
                //if(regex.GroupCount >= returnMatchNr) then begin
                //    Result := regex.Groups[returnMatchNr];
                //end;
            end;
        finally
            RegEx.Free;
        end;

	end;

	function getFirstCVPA(misc: IInterface): IInterface;
	var
		cvpa, firstElem: IInterface;
	begin
		Result := nil;
		cvpa := ElementByPath(misc, 'CVPA');
		if(not assigned(cvpa)) then exit;

		firstElem := ElementByIndex(cvpa, 0);
		if(not assigned(firstElem)) then exit;

		Result := pathLinksTo(firstElem, 'Component');
	end;

	function findObjectByEdidCached(edid: string): IInterface;
	var
		i: integer;
	begin
		i := edidLookupCache.indexOf(edid);
		if(i >= 0) then begin
			Result := ObjectToElement(edidLookupCache.Objects[i]);
			exit;
		end;

		Result := FindObjectByEdid(edid);
		edidLookupCache.addObject(edid, Result);
	end;

	procedure registerResource(vrEdid, realEdid, groupEdid, scrapEdid: string);
	var
		vrElem, realElem, groupElem, scrapElem: IInterface;
		vrFormStr: string;
		curEntry: TJsonObject;
	begin
		vrElem := findObjectByEdidCached(vrEdid);
		if(not assigned(vrElem)) then begin
			AddMessage('Failed to register resource '+vrEdid+': not found');
			exit;
		end;

		realElem := findObjectByEdidCached(realEdid);
		groupElem := findObjectByEdidCached(groupEdid);
		scrapElem := findObjectByEdidCached(scrapEdid);

		if (not assigned(realElem)) or (not assigned(groupElem)) or (not assigned(scrapElem)) then begin
			AddMessage('Failed to register resource '+vrEdid+': couldn''nt found one of '+realEdid+', '+groupEdid+', '+scrapEdid);
			exit;
		end;

		vrFormStr := FormToAbsStr(vrElem);
		curEntry := resourceLookupTable.O[vrFormStr];

		curEntry.S[RESOURCE_COMPLEXITY_MINIMAL] := FormToAbsStr(scrapElem);
		curEntry.S[RESOURCE_COMPLEXITY_CATEGORY]:= FormToAbsStr(groupElem);
		curEntry.S[RESOURCE_COMPLEXITY_FULL] 	:= FormToAbsStr(realElem);
	end;

	procedure registerSimpleResource(vrEdid, realEdid: string);
	begin
		registerResource(vrEdid, realEdid, realEdid, realEdid);
	end;

	procedure registerScrapResource(vrEdid, realEdid, groupEdid: string);
	begin
		registerResource(vrEdid, realEdid, groupEdid, 'SS2_c_HQ_SimpleResource_Scrap');
	end;

	procedure registerSupplyResource(vrEdid, realEdid, groupEdid: string);
	begin
		registerResource(vrEdid, realEdid, groupEdid, 'SS2_c_HQ_SimpleResource_Supplies');
	end;

	procedure loadResourceGroups();
	begin
		registerSimpleResource('SS2_VirtualResource_Caps', 'Caps001');

		registerScrapResource('SS2_VirtualResource_RareMaterials_NuclearMaterial', 'c_NuclearMaterial', 'SS2_c_HQ_CategoryResource_RareMaterials');
		registerScrapResource('SS2_VirtualResource_RareMaterials_Gold', 'c_Gold', 'SS2_c_HQ_CategoryResource_RareMaterials');
		registerScrapResource('SS2_VirtualResource_RareMaterials_FiberOptics', 'c_FiberOptics', 'SS2_c_HQ_CategoryResource_RareMaterials');
		registerScrapResource('SS2_VirtualResource_RareMaterials_Crystal', 'c_Crystal', 'SS2_c_HQ_CategoryResource_RareMaterials');
		registerScrapResource('SS2_VirtualResource_RareMaterials_BallisticFiber', 'c_AntiBallisticFiber', 'SS2_c_HQ_CategoryResource_RareMaterials');
		registerScrapResource('SS2_VirtualResource_RareMaterials_Antiseptic', 'c_Antiseptic', 'SS2_c_HQ_CategoryResource_RareMaterials');

		registerScrapResource('SS2_VirtualResource_OrganicMaterials_Oil', 'c_Oil', 'SS2_c_HQ_CategoryResource_OrganicMaterials');
		registerScrapResource('SS2_VirtualResource_OrganicMaterials_Leather', 'c_Leather', 'SS2_c_HQ_CategoryResource_OrganicMaterials');
		registerScrapResource('SS2_VirtualResource_OrganicMaterials_Fertilizer', 'c_Fertilizer', 'SS2_c_HQ_CategoryResource_OrganicMaterials');
		registerScrapResource('SS2_VirtualResource_OrganicMaterials_Cork', 'c_Cork', 'SS2_c_HQ_CategoryResource_OrganicMaterials');
		registerScrapResource('SS2_VirtualResource_OrganicMaterials_Cloth', 'c_Cloth', 'SS2_c_HQ_CategoryResource_OrganicMaterials');
		registerScrapResource('SS2_VirtualResource_OrganicMaterials_Ceramic', 'c_Ceramic', 'SS2_c_HQ_CategoryResource_OrganicMaterials');
		registerScrapResource('SS2_VirtualResource_OrganicMaterials_Bone', 'c_Bone', 'SS2_c_HQ_CategoryResource_OrganicMaterials');
		registerScrapResource('SS2_VirtualResource_OrganicMaterials_Adhesive', 'c_Adhesive', 'SS2_c_HQ_CategoryResource_OrganicMaterials');
		registerScrapResource('SS2_VirtualResource_OrganicMaterials_Acid', 'c_Acid', 'SS2_c_HQ_CategoryResource_OrganicMaterials');

		registerScrapResource('SS2_VirtualResource_MachineParts_Springs', 'c_Springs', 'SS2_c_HQ_CategoryResource_MachineParts');
		registerScrapResource('SS2_VirtualResource_MachineParts_Silver', 'c_Silver', 'SS2_c_HQ_CategoryResource_MachineParts');
		registerScrapResource('SS2_VirtualResource_MachineParts_Screws', 'c_Screws', 'SS2_c_HQ_CategoryResource_MachineParts');
		registerScrapResource('SS2_VirtualResource_MachineParts_Rubber', 'c_Rubber', 'SS2_c_HQ_CategoryResource_MachineParts');
		registerScrapResource('SS2_VirtualResource_MachineParts_Plastic', 'c_Plastic', 'SS2_c_HQ_CategoryResource_MachineParts');
		registerScrapResource('SS2_VirtualResource_MachineParts_Lead', 'c_Lead', 'SS2_c_HQ_CategoryResource_MachineParts');
		registerScrapResource('SS2_VirtualResource_MachineParts_Gears', 'c_Gears', 'SS2_c_HQ_CategoryResource_MachineParts');
		registerScrapResource('SS2_VirtualResource_MachineParts_Copper', 'c_Copper', 'SS2_c_HQ_CategoryResource_MachineParts');
		registerScrapResource('SS2_VirtualResource_MachineParts_Circuitry', 'c_Circuitry', 'SS2_c_HQ_CategoryResource_MachineParts');

		registerScrapResource('SS2_VirtualResource_BuildingMaterials_Wood', 'c_Wood', 'SS2_c_HQ_CategoryResource_BuildingMaterials');
		registerScrapResource('SS2_VirtualResource_BuildingMaterials_Steel', 'c_Steel', 'SS2_c_HQ_CategoryResource_BuildingMaterials');
		registerScrapResource('SS2_VirtualResource_BuildingMaterials_Glass', 'c_Glass', 'SS2_c_HQ_CategoryResource_BuildingMaterials');
		registerScrapResource('SS2_VirtualResource_BuildingMaterials_Fiberglass', 'c_Fiberglass', 'SS2_c_HQ_CategoryResource_BuildingMaterials');
		registerScrapResource('SS2_VirtualResource_BuildingMaterials_Concrete', 'c_Concrete', 'SS2_c_HQ_CategoryResource_BuildingMaterials');
		registerScrapResource('SS2_VirtualResource_BuildingMaterials_Asbestos', 'c_Asbestos', 'SS2_c_HQ_CategoryResource_BuildingMaterials');
		registerScrapResource('SS2_VirtualResource_BuildingMaterials_Aluminum', 'c_Aluminum', 'SS2_c_HQ_CategoryResource_BuildingMaterials');


		// Supplies
			// Ammo
		registerSupplyResource('SS2_VirtualResource_Supplies_Ammo_Ballistic', 'SS2_c_ComponentResource_Ammo_Ballistic', 'SS2_c_HQ_CategoryResource_Ammo');
		registerSupplyResource('SS2_VirtualResource_Supplies_Ammo_Energy', 'SS2_c_ComponentResource_Ammo_Energy', 'SS2_c_HQ_CategoryResource_Ammo');
		registerSupplyResource('SS2_VirtualResource_Supplies_Ammo_Explosive', 'SS2_c_ComponentResource_Ammo_Explosive', 'SS2_c_HQ_CategoryResource_Ammo');
			// Armor
		registerSupplyResource('SS2_VirtualResource_Supplies_Armor_Heavy', 'SS2_c_ComponentResource_Armor_Heavy', 'SS2_c_HQ_CategoryResource_Armor');
		registerSupplyResource('SS2_VirtualResource_Supplies_Armor_Makeshift', 'SS2_c_ComponentResource_Armor_Makeshift', 'SS2_c_HQ_CategoryResource_Armor');
		registerSupplyResource('SS2_VirtualResource_Supplies_Armor_Power', 'SS2_c_ComponentResource_Armor_Power', 'SS2_c_HQ_CategoryResource_Armor');
		registerSupplyResource('SS2_VirtualResource_Supplies_Armor_Standard', 'SS2_c_ComponentResource_Armor_Standard', 'SS2_c_HQ_CategoryResource_Armor');
			// Chems
		registerSupplyResource('SS2_VirtualResource_Supplies_Chems_AntiRadiation', 'SS2_c_ComponentResource_Chems_AntiRadiation', 'SS2_c_HQ_CategoryResource_Chems');
		registerSupplyResource('SS2_VirtualResource_Supplies_Chems_Cures', 'SS2_c_ComponentResource_Chems_Cures', 'SS2_c_HQ_CategoryResource_Chems');
		registerSupplyResource('SS2_VirtualResource_Supplies_Chems_Enhancements', 'SS2_c_ComponentResource_Chems_Enhancements', 'SS2_c_HQ_CategoryResource_Chems');
		registerSupplyResource('SS2_VirtualResource_Supplies_Chems_Stims', 'SS2_c_ComponentResource_Chems_Stims', 'SS2_c_HQ_CategoryResource_Chems');
			// Weapon parts
		registerSupplyResource('SS2_VirtualResource_Supplies_WeaponParts_Heavy', 'SS2_c_ComponentResource_WeaponParts_Heavy', 'SS2_c_HQ_CategoryResource_WeaponParts');
		registerSupplyResource('SS2_VirtualResource_Supplies_WeaponParts_Makeshift', 'SS2_c_ComponentResource_WeaponParts_Makeshift', 'SS2_c_HQ_CategoryResource_WeaponParts');
		registerSupplyResource('SS2_VirtualResource_Supplies_WeaponParts_Standard', 'SS2_c_ComponentResource_WeaponParts_Standard', 'SS2_c_HQ_CategoryResource_WeaponParts');
	end;


	procedure loadResources();
	var
		resName: string;
		i, len: integer;
		flst, curAv: IInterface;
	begin
		flst := FindObjectByEdid('SS2_VirtualResourceAVsList');
		len := getFormListLength(flst);

		for i:=0 to len-1 do begin
			curAv := getFormListEntry(flst, i);
			resName := getResourceAvName(curAv);
			//AddMessage('Found resource: '+resName);
			addObjectDupIgnore(listRoomResources, resName, curAv);
		end;
	end;


	procedure loadForRoomUpgade();
	begin

		loadResources();

		loadResourceGroups();
	end;

	function findHqName(hqRef: IInterface): string;
	var
		maybeName: string;
	begin
		// TODO think of something better
		maybeName := EditorID(hqRef);
		if(maybeName <> '') then begin
			Result := maybeName;
			exit;
		end;

		maybeName := DisplayName(hqRef);
		if(maybeName <> '') then begin
			Result := maybeName;
			exit;
		end;

		Result := IntToHex(FormID(hqRef), 8);
	end;

	function findHqNameShort(hqRef: IInterface): string;
	var
		longName, shortName: string;
	begin
		longName := findHqName(hqRef);

		shortName := regexExtract(longName, '_([^_]+)$', 1);
		if(shortName <> '') then begin
			Result := shortName;
			exit;
		end;

		Result := longName;
	end;

	procedure setStringListAt(list: TStringList; index: integer; str: string; e: IInterface);
	var
		i: integer;
	begin
		while(list.size <= index) do begin
			list.add('');
		end;
		list[index] := str;
		list.Objects[index] := e;

	end;

	function getHqManagerScript(e: IInterface): IInterface;
	var
        curScript, scripts: IInterface;
        i: integer;
		curScriptName: string;
    begin
        Result := nil;
        e := WinningOverrideOrSelf(e);
        scripts := ElementByPath(e, 'VMAD - Virtual Machine Adapter\Scripts');

        for i := 0 to ElementCount(scripts)-1 do begin
            curScript := ElementByIndex(scripts, i);

			if (assigned(getScriptProp(curScript, 'HQRef'))) then begin
				// might be
				curScriptName := GetElementEditValues(curScript, 'scriptName');

				if (checkScriptExtendsCached(curScriptName, 'SimSettlementsV2:HQ:Library:Quests:SpecificHQManager')) then begin
					Result := curScript;
					exit;
				end;
			end;
        end;

	end;

	procedure loadHQsFromFile(fromFile:  IInterface);
	var i, j: integer;
		curRec, group, curScript, hqRef: IInterface;
		edid, hqName, curFileName, curHqKey: string;
	begin
		curFileName := GetFileName(fromFile);

		// hack: skip vanilla files
		if(Pos(curFileName, readOnlyFiles) > 0) then begin
			exit;
		end;

		group := GroupBySignature(fromFile, 'QUST');
		startProgress('Checking quests from '+GetFileName(fromFile), ElementCount(group));
		for i:=0 to ElementCount(group)-1 do begin
			curRec := WinningOverrideOrSelf(ElementByIndex(group, i));
			edid := EditorID(curRec);


			// maybe do this the other way round: find a script which has HQRef, then check if it extends SimSettlementsV2:HQ:Library:Quests:SpecificHQManager
			curScript := getHqManagerScript(curRec);

			if(assigned(curScript)) then begin
				hqRef := getScriptProp(curScript, 'HQRef');
				if(not assigned(hqRef)) then begin
					// hmmm...?
					//hqRef := SS2_HQ_WorkshopRef_GNN;
					AddMessage('HQ Manager without HQ ref? '+edid);
					continue;
				end;

				if(EditorID(hqRef) = 'SS2_HQ_WorkshopRef_GNN') then begin
					SS2_HQ_WorkshopRef_GNN := hqRef;
				end;

				hqName := findHqName(hqRef);

				curHqKey := FormToAbsStr(hqRef);
//
				currentCacheFile.O['files'].O[curFileName].O['HQs'].S[curHqKey] := FormToAbsStr(curRec);
				// actually load into the stringlist later
{
				j := listHQRefs.indexOf(hqName);

				if(j < 0) then begin
					j := listHQRefs.addObject(hqName, hqRef);
					setStringListAt(listHqManagers, j, EditorID(curRec), curRec);
				end;
}

				// addObjectDupIgnore(listHqManagers, edid, curRec);
			end;
			updateProgress(i);
		end;
		endProgress();
	end;

	{
	procedure loadHQs();
	var
		curRef: IInterface;
		i, numData, numRefs: integer;
		hqName, edid: string;
		curFile: IInterface;
	begin
		numData := MasterCount(targetFile);

		startProgress('Loading HQs...', numData);
		for i:=0 to numData-1 do begin
			curFile := MasterByIndex(targetFile, i);
			loadHQsFromFile(curFile);
			updateProgress(i);
		end;
		endProgress();

	end;
	}

	function findLinkedRef(ref, kw: IInterface): IInterface;
	var
		linkedRefs, curRef, curKw: IInterface;
		i: integer;
	begin
		linkedRefs := ElementByPath(ref, 'Linked References');
		for i:=0 to ElementCount(linkedRefs)-1 do begin
			curRef := ElementByIndex(linkedRefs, i);
			curKw := PathLinksTo(curRef, 'Keyword/Ref');
			if(FormsEqual(kw, curKw)) then begin
				Result := PathLinksTo(curRef, 'Ref');
				exit;
			end;
		end;
	end;

	procedure loadDepartmentsForHq(hq, fromFile: IInterface);
	var
		base, curRef, script, linkedTarget: IInterface;
		i: integer;
		departmentName, curFileName, curHqKey: string;
		curFormID: cardinal;
	begin
		// iterate HQs
		curFileName := GetFileName(fromFile);
		curHqKey := FormToAbsStr(hq);

		for i:=0 to ReferencedByCount(hq)-1 do begin
			curRef := WinningOverrideOrSelf(ReferencedByIndex(hq, i));
			if (Signature(curRef) <> 'REFR') then begin
				continue;
			end;

			// skip stuff not from this file for now
			if(not FilesEqual(fromFile, GetFile(curRef))) then begin
				continue;
			end;

			base := PathLinksTo(curRef, 'NAME');
			if (Signature(base) <> 'ACTI') then begin
				continue;
			end;

			linkedTarget := findLinkedRef(curRef, WorkshopItemKeyword);
			if (not FormsEqual(linkedTarget, hq)) then begin
				continue;
			end;

			script := getScript(base, 'SimSettlementsV2:HQ:Library:ObjectRefs:DepartmentObject');
			if(assigned(script)) then begin
				// found!
				departmentName := GetElementEditValues(base, 'FULL');
				//addObjectDupIgnore(listDepartmentObjects, departmentName, curRef);
				curFormID := getElementLocalFormId(curRef);

				currentCacheFile.O['files'].O[curFileName].O['HQData'].O[curHqKey].O['Departments'].S[departmentName] := IntToHex(curFormID, 8);

			end;



			// [REFR:04004072] (places SS2_HQ_DepartmentObject_Administration "Administration" [ACTI:04004071] in GRUP Cell Persistent Children of AAWH "HQ" [CELL:04000FA7])
			// must be:
			//	NAME - Base:
			//		activator
			// 		start with SS2_HQ_DepartmentObject_ (maybe?)
			// 		has script: SimSettlementsV2:HQ:Library:ObjectRefs:DepartmentObject
			// 	Linked References has entry with:
			//		Keyword/Ref = WorkshopItemKeyword [KYWD:00054BA6]
			//		Ref = targetHQ
		end;
	end;

	procedure loadHqDepartments(fromFile: IInterface);
	var
		i, j: integer;
		curFileName, hqString: string;
		curFileObj, curHqObj: TJsonObject;
		curHq: IInterface;
		filesEntry: TJsonObject;
	begin
		filesEntry := currentCacheFile.O['files'];
		for i:=0 to filesEntry.count-1 do begin
			curFileName := filesEntry.names[i];
			curHqObj := filesEntry.O[curFileName].O['HQs'];

			for j:=0 to curHqObj.count-1 do begin
				hqString := curHqObj.names[j];

				curHq := WinningOverrideOrSelf(AbsStrToForm(hqString));
				loadDepartmentsForHq(curHq, fromFile);
			end;

		end;
		{
		$currentCacheFile = [
			'files' => [
				'somefile.esp' => [
					'HQs' => [
						FormToAbsStr(ref) => FormToAbsStr(manager),
					],
				],
			],
		],
		}
	end;

	function getManagerForHq(hq: IInterface): IInterface;
	var
		i, j: integer;
		curFileName, hqString, searchString, managerString: string;
		curHqObj: TJsonObject;
		curHq: IInterface;
		filesEntry: TJsonObject;
	begin
		Result := nil;
		filesEntry := currentCacheFile.O['files'];

		searchString := FormToAbsStr(hq);

		for i:=0 to filesEntry.count-1 do begin
			curFileName := filesEntry.names[i];
			curHqObj := filesEntry.O[curFileName].O['HQs'];

			managerString := filesEntry.O[curFileName].O['HQs'].S[searchString];
			if(managerString <> '') then begin

				Result := WinningOverrideOrSelf(AbsStrToForm(managerString));
				exit;
			end;
		end;
        AddMessage('=== ERROR: failed to find manager for HQ ===');
	end;

	procedure loadKeywordsFromFile(fromFile:  IInterface);
	var i: integer;
		curRec, group: IInterface;
		edid: string;
	begin
		group := GroupBySignature(fromFile, 'KYWD');
		startProgress('Loading keywords from '+GetFileName(fromFile), ElementCount(group));
		for i:=0 to ElementCount(group)-1 do begin
			curRec := ElementByIndex(group, i);
			edid := EditorID(curRec);

			if(strStartsWithSS2(edid, 'Tag_RoomShape')) then begin
				// AddMessage('Found RoomShape! '+EditorID(curRec));
				addObjectDupIgnore(listRoomShapes, edid, curRec);
			end;

            if(strStartsWithSS2(edid, 'WorkshopMenu_HQ_Facilities_Construction_')) then begin
                // use a better prefix
				addObjectDupIgnore(listKeywordsConstruct, stripSS2Prefix(edid, 'WorkshopMenu_HQ_Facilities_Construction_'), curRec);
			end;

            if(strStartsWithSS2(edid, 'WorkshopMenu_HQ_Engineering_Upgrades_')) then begin
				addObjectDupIgnore(listKeywordsUpgrade, stripSS2Prefix(edid, 'WorkshopMenu_HQ_Engineering_Upgrades_'), curRec);
			end;

            // just all?
            if(strStartsWithSS2(edid, 'WorkshopMenu_HQ_')) then begin
				addObjectDupIgnore(listKeywordsTech, stripSS2Prefix(edid, 'WorkshopMenu_HQ_'), curRec);
			end;

            //listKeywordsTech

			updateProgress(i);
		end;
		endProgress();
	end;

	procedure loadActivatorsFromFile(fromFile:  IInterface);
	var i: integer;
		curRec, group: IInterface;
		edid: string;
	begin
		group := GroupBySignature(fromFile, 'ACTI');
		startProgress('Loading activators from '+GetFileName(fromFile), ElementCount(group));
		for i:=0 to ElementCount(group)-1 do begin
			curRec := ElementByIndex(group, i);
			edid := EditorID(curRec);

			if(strStartsWithSS2(edid, 'HQ_DepartmentObject_')) then begin
				// AddMessage('Found Department! '+EditorID(curRec));
				addObjectDupIgnore(listDepartmentObjects, edid, curRec);
			end;
			updateProgress(i);
		end;
		endProgress();
	end;



	{
		Checks if string starts with either SS2_+prefix or SS2C2_+prefix
	}
	function strStartsWithSS2(str, prefix: string): boolean;
	begin
		if(strStartsWithCI(str, 'SS2_'+prefix)) then begin
			Result := true;
			exit;
		end;

		if(strStartsWithCI(str, 'SS2C2_'+prefix)) then begin
			Result := true;
			exit;
		end;

		Result := false;
	end;

    function stripSS2Prefix(str, prefix: string): string;
    begin
        Result := stripPrefix('SS2_'+prefix, str);
        Result := stripPrefix('SS2C2_'+prefix, Result);
    end;

	function findHqByLocation(loc: IInterface): IInterface;
	var
		i: integer;
		curHq, curLoc: IInterface;
	begin
		Result := nil;

		for i:=0 to listHQRefs.count-1 do begin
			curHq := ObjectToElement(listHQRefs.Objects[i]);
			curLoc := getRefLocation(forHq);
			if(Equals(curLoc, loc)) then begin
				Result := curHq;
				exit;
			end;
		end;
	end;

	function getHqForRoomConfig(e: IInterface): IInterface;
	var
		i: integer;
		curScript, primaryDepartment, linkedRefs, curKw, curRef, linkedEntry: IInterface;
		RoomUpgradeSlots, curSlot, curSlotScript, HQLocation: IInterface;
	begin
		//AddMessage('Searching HQ for '+EditorID(e));
        e := WinningOverrideOrSelf(e);
		curScript := getScript(e, 'SimSettlementsV2:HQ:Library:MiscObjects:RequirementTypes:ActionTypes:HQRoomConfig');

		primaryDepartment := getScriptProp(curScript, 'PrimaryDepartment');
		// primary department might be undefined...
		if(assigned(primaryDepartment)) then begin
			// this is a REFR
            primaryDepartment := WinningOverrideOrSelf(primaryDepartment);
			linkedRefs := ElementByPath(primaryDepartment, 'Linked References');
			for i:=0 to ElementCount(linkedRefs)-1 do begin
				linkedEntry := ElementByIndex(linkedRefs, i);
				curKw := PathLinksTo(linkedEntry, 'Keyword/Ref');
				curRef := PathLinksTo(linkedEntry, 'Ref');

				if(EditorID(curKw) = 'WorkshopItemKeyword') then begin
					//AddMessage('Found HQ '+EditorID(curRef)+' via linked ref');
					Result := curRef;
					exit;
				end;
			end;
		end;

		// otherwise try going via the upgrade
		RoomUpgradeSlots := getScriptProp(curScript, 'RoomUpgradeSlots');
		for i:=0 to ElementCount(RoomUpgradeSlots)-1 do begin
			curSlot := getObjectFromProperty(RoomUpgradeSlots, i);
            curSlot := WinningOverrideOrSelf(curSlot);
			curSlotScript := getScript(curSlot, 'SimSettlementsV2:HQ:Library:MiscObjects:RequirementTypes:HQRoomUpgradeSlot_GNN');
			if(assigned(curSlotScript)) then begin
				//AddMessage('because of _GNN script');
				Result := SS2_HQ_WorkshopRef_GNN;
				exit;
			end;
			curSlotScript := getScript(curSlot, 'simsettlementsv2:hq:library:miscobjects:requirementtypes:hqroomupgradeslot');
			if(assigned(curSlotScript)) then begin
				HQLocation := getScriptProp(curSlotScript, 'HQLocation');
				Result := findHqByLocation(HQLocation);
				if(assigned(Result)) then begin
					exit;
				end;
			end;
		end;

		// finally, assume default HQ and hope for the best
		//AddMessage('Using default HQ');
		Result := SS2_HQ_WorkshopRef_GNN;
	end;

    procedure loadRoomUpgradeSlots(curFileName: string; roomUpgrade, roomUpgradeScript: IInterface);
    var
        AdditionalUpgradeSlots, curSlot, curHq, roomConfig: IInterface;
        i: integer;
        curHqKey: string;
    begin
        AdditionalUpgradeSlots := getScriptProp(roomUpgradeScript, 'AdditionalUpgradeSlots');
        if(not assigned(AdditionalUpgradeSlots)) then begin
            exit;
        end;

        curHq := getHqFromRoomUpdate(roomUpgradeScript);
        if(not assigned(curHq)) then begin
            curHq := SS2_HQ_WorkshopRef_GNN;
        end;

        roomConfig := WinningOverrideOrSelf(findRoomConfigFromRoomUpgrade(roomUpgrade));

        curHqKey := FormToAbsStr(curHq);

        for i:=0 to ElementCount(AdditionalUpgradeSlots)-1 do begin
            curSlot := getObjectFromProperty(AdditionalUpgradeSlots, i);
            addRoomConfigSlot(curFileName, curHqKey, roomConfig, curSlot);
        end;

    end;

    procedure addRoomConfigSlot(curFileName, hqKey: string; roomConfig, slot: IInterface);
    var
        slotJson: TJsonObject;
        slotName, slotNameBase, slotHexId, existingSlotHexId, roomConfigKey: string;
        curFormID: cardinal;
        i: integer;
        canInsert: boolean;
    begin
        // first of all, index by roomconfig
        roomConfigKey := FormToAbsStr(roomConfig);
        slotJson := currentCacheFile.O['files'].O[curFileName].O['HQData'].O[hqKey].O['RoomConfigSlots'].O[roomConfigKey];

        curFormID := getElementLocalFormId(slot);
        slotNameBase := GetRoomSlotName(slot);
        slotHexId := IntToHex(curFormID, 8);

        slotName := slotNameBase;


        i:=1;
        canInsert := false;
        while (not canInsert) do begin
            existingSlotHexId := slotJson.S[slotName];
            if ((existingSlotHexId = '') or (existingSlotHexId = slotHexId)) then begin
                canInsert := true;
            end else begin
                i := i + 1;
                slotName := slotNameBase + ' ' + IntToStr(i);
            end;
        end;

        slotJson.S[slotName] := slotHexId;
    end;



    procedure loadRoomConfig(curFileName: string; roomConfig, roomConfigScript: IInterface);
    var
        curName, curHqKey, slotName, slotHexId, existingSlotHexId: string;
        curFormID: cardinal;
        curHq, RoomUpgradeSlots, curSlot: IInterface;
        slotJson: TJsonObject;
        i: integer;
    begin
        roomConfig := WinningOverrideOrSelf(roomConfig);
        // yes
        curName := getRoomConfigName(roomConfig);
        // addObjectDupIgnore(listRoomConfigs, curName, curRec);
        curFormID := getElementLocalFormId(roomConfig);
        curHq := getHqForRoomConfig(roomConfig);
        curHqKey := FormToAbsStr(curHq);

        currentCacheFile.O['files'].O[curFileName].O['HQData'].O[curHqKey].O['RoomConfigs'].S[curName] := IntToHex(curFormID, 8);

        // also slots
        RoomUpgradeSlots := getScriptProp(roomConfigScript, 'RoomUpgradeSlots');

        slotJson := currentCacheFile.O['files'].O[curFileName].O['HQData'].O[curHqKey].O['RoomConfigSlots'];

		for i:=0 to ElementCount(RoomUpgradeSlots)-1 do begin
			curSlot := getObjectFromProperty(RoomUpgradeSlots, i);

            addRoomConfigSlot(curFileName, curHqKey, roomConfig, curSlot);
		end;
    end;

	procedure loadSoundsFromFile(fromFile:  IInterface);
    var i: integer;
		curRec, group: IInterface;
		edid, curName, curFileName: string;
	begin
		curFileName := GetFileName(fromFile);
		group := GroupBySignature(fromFile, 'SNDR');
		startProgress('Loading Sounds from '+GetFileName(fromFile), ElementCount(group));
		for i:=0 to ElementCount(group)-1 do begin

			curRec := ElementByIndex(group, i);
			edid := EditorID(curRec);


			updateProgress(i);
			if(strStartsWith(edid, 'SS2_SFX_HQProjectType_')) then begin

                curName := stripPrefix('SS2_SFX_HQProjectType_', edid);

                addObjectDupIgnore(listPutDownSounds, curName, curRec);

                continue;
				// SimSettlementsV2:HQ:Library:MiscObjects:HQRoomFunctionality
			end;
		end;
		endProgress();

    end;

	procedure loadCmposFromFile(fromFile:  IInterface);
    var i: integer;
		curRec, group, curHq, curScript: IInterface;
		edid, curName, curFileName, curHqKey: string;
		curFormID: cardinal;
	begin
		curFileName := GetFileName(fromFile);
		group := GroupBySignature(fromFile, 'CMPO');
		startProgress('Loading CMPOs from '+GetFileName(fromFile), ElementCount(group));
		for i:=0 to ElementCount(group)-1 do begin

			curRec := ElementByIndex(group, i);
			edid := EditorID(curRec);

			updateProgress(i);

            if(strStartsWith(edid, 'SS2_c_')) then begin
                // but ignore all SS2_c_HQ_ and SS2_c_ComponentResource_
                if(not strStartsWith(edid, 'SS2_c_HQ_') and not strStartsWith(edid, 'SS2_c_ComponentResource_')) then begin
                    curName := getElementEditValues(curRec, 'FULL');
                    addObjectDupIgnore(listRoomResources, curName, curRec);
                end;
            end;

		end;
		endProgress();
    end;

	procedure loadMiscsFromFile(fromFile:  IInterface);
	var i: integer;
		curRec, group, curHq, curScript: IInterface;
		edid, curName, curFileName, curHqKey: string;
		curFormID: cardinal;
	begin
		curFileName := GetFileName(fromFile);
		group := GroupBySignature(fromFile, 'MISC');
		startProgress('Loading MISCs from '+GetFileName(fromFile), ElementCount(group));
		for i:=0 to ElementCount(group)-1 do begin

			curRec := ElementByIndex(group, i);
			edid := EditorID(curRec);

			updateProgress(i);

			if(pos('HQ_ActionGroup_', edid) > 0) then begin

				if(edid <> 'SS2_HQ_ActionGroup_Template') then begin
					//SimSettlementsV2:HQ:Library:MiscObjects:ActionGroupTypes:DepartmentHQActionGroup
					curScript := findScriptInElementByNameCached(curRec, 'SimSettlementsV2:HQ:Library:MiscObjects:HQActionGroup');
					if(assigned(curScript)) then begin
						curHq := getHqFromRoomActionGroup(curRec, curScript);
						// theoretically, this might be unset
						if(not assigned(curHq)) then begin
							curHq := SS2_HQ_WorkshopRef_GNN;
						end;

						curHqKey := FormToAbsStr(curHq);

						curFormID := getElementLocalFormId(curRec);
						// put into cache file
						currentCacheFile.O['files'].O[curFileName].O['HQData'].O[curHqKey].O['ActionGroups'].S[edid] := IntToHex(curFormID, 8);
						// load into the proper stringlist later

						//if(FormsEqual(curHq, targetHQ)) then begin
							//addObjectDupIgnore(listActionGroups, edid, curRec);
						//end;
					end;
				end;
				continue;
			end;

			if(pos('_Action_AssignRoomConfig_', edid) > 0) then begin
                // room config
				curScript := getScript(curRec, 'SimSettlementsV2:HQ:Library:MiscObjects:RequirementTypes:ActionTypes:HQRoomConfig');
				if(assigned(curScript)) then begin
                    loadRoomConfig(curFileName, curRec, curScript);
				end;
				continue;
			end;

			if(strStartsWithSS2(edid, 'HQRoomFunctionality_')) then begin
                // meh, just believe it's correct, no script check. we don't really need the script here.
                curName := GetElementEditValues(curRec, 'FULL');
                addObjectDupIgnore(listRoomFuncs, curName, curRec);

                continue;
			end;

			if(strStartsWithSS2(edid, 'HQResourceToken_WorkEnergy_')) then begin
				addObjectDupIgnore(listRoomResources, GetElementEditValues(curRec, 'FULL'), curRec);
                continue;
			end;

            // load room upgrades
            if (pos('_Action_RoomUpgrade_', edid) > 0) or (pos('_Action_RoomConstruction_', edid) > 0) then begin
				curScript := getScript(curRec, 'SimSettlementsV2:HQ:BaseActionTypes:HQRoomUpgrade');
				if (assigned(curScript)) then begin
                    loadRoomUpgradeSlots(curFileName, curRec, curScript);
				end;
				continue;
			end;

            // load action types for tech/other
            if (pos('Action', edid) > 0) and (pos('Template', edid) > 0) then begin
                addObjectDupIgnore(listTechActionTypes, edid, curRec);
				// curScript := getScript(curRec, 'SimSettlementsV2:HQ:BaseActionTypes:HQRoomUpgrade');
				//if (assigned(curScript)) then begin
                  //  loadRoomUpgradeSlots(curFileName, curRec, curScript);
				//end;
				continue;
			end;

		end;
		endProgress();
	end;

	procedure loadHQDependentFormsFromFile(fromFile: IInterface);
	begin
		loadHqDepartments(fromFile);
	end;

	procedure loadFormsFromFile(fromFile: IInterface);
	begin
		AddMessage('Loading forms from file '+GetFileName(fromFile));
		startProgress('', 6);
		updateProgress(0);
		loadHQsFromFile(fromFile);
		updateProgress(1);
		loadKeywordsFromFile(fromFile);
		// loadActivatorsFromFile(fromFile);
		updateProgress(2);
		loadMiscsFromFile(fromFile);
		updateProgress(3);
		loadCmposFromFile(fromFile);
		updateProgress(4);
		loadSoundsFromFile(fromFile);
		updateProgress(5);
		loadHQDependentFormsFromFile(fromFile);
		// loadQuestsFromFile(fromFile);
		endProgress();
	end;

	procedure appendObjectLists(targetList: TStringList; sourceList: TStringList);
	var
		i: integer;
		curObj, curFile: IInterface;
		curFileName: string;
		curFormId: cardinal;
	begin
		for i:=0 to sourceList.count-1 do begin
			curObj := ObjectToElement(sourceList.Objects[i]);
			curFile := GetFile(curObj);
			if(not FilesEqual(targetFile, curFile)) then begin
				curFormId := getLocalFormId(targetFile, FormId(curObj));
				targetList.add(IntToHex(curFormId, 8) + '=' + GetFileName(curFile));
			end;
		end;
	end;

	procedure writeObjectList(sourceList: TStringList; targetJson: TJsonObject);
	var
		i: integer;
		curObj, curFile: IInterface;
		curFileName: string;
		curFormId: cardinal;
		curSubJson: TJsonObject;
	begin
		for i:=0 to sourceList.count-1 do begin
			curObj := ObjectToElement(sourceList.Objects[i]);
			curFile := GetFile(curObj);
			if(not FilesEqual(targetFile, curFile)) then begin
				curFormId := getLocalFormId(targetFile, FormId(curObj));

				curSubJson := targetJson.A[GetFileName(curFile)].addObject();
				curSubJson.S['FormID'] := IntToHex(curFormId, 8);
				curSubJson.S['Text'] := sourceList[i];
			end;
		end;
	end;

	procedure writeObjectListToCacheFile(sourceList: TStringList; jsonKey: string);
	var
		i: integer;
		curText, curFileName: string;
		curObj, curFile: IInterface;
		curFormId: cardinal;
	begin

		for i:=0 to sourceList.count-1 do begin
			curText := sourceList[i];
			curObj := ObjectToElement(sourceList.Objects[i]);

			curFile := GetFile(curObj);
			curFileName := GetFileName(curFile);

			curFormId := getElementLocalFormId(curObj);

			//AddMessage('writing '+curText+' -> ');
			currentCacheFile.O['files'].O[curFileName].O[jsonKey].S[curText] := IntToHex(curFormId, 8);
			//AddMessage('What '+currentCacheFile.O['files'].O[curFileName].O[jsonKey].O[curText].toString());
		end;

		// okay, what
	end;

	procedure writeStringList(sourceList: TStringList; targetJson: TJsonArray);
	var
		i: integer;
		curObj, curFile: IInterface;
		curFileName: string;
		curFormId: cardinal;
	begin
		for i:=0 to sourceList.count-1 do begin
			targetJson.add(sourceList[i]);
		end;
	end;

	function getTargetHqKey(): string;
	begin
		Result := FormToAbsStr(targetHq);
	end;

	procedure saveListsToCache(masterList: TStringList);
	var
		i, realFileAge: integer;
		hqKey, curFileName: string;
		filesEntry, filesEntries: TJsonObject;
	begin
		//cacheJson := TJsonObject.create();
		if(not assigned(currentCacheFile)) then begin
			currentCacheFile := TJsonObject.create;
		end;

        currentCacheFile.I['version'] := cacheFileVersion;
		currentCacheFile.S['DefaultHQ'] := FormToAbsStr(SS2_HQ_WorkshopRef_GNN);
		// simple stuff
		writeObjectListToCacheFile(listRoomShapes, 'RoomShapes');
		writeObjectListToCacheFile(listKeywordsUpgrade, 'UpgradeKeywords');
		writeObjectListToCacheFile(listKeywordsConstruct, 'ConstructKeywords');
		writeObjectListToCacheFile(listKeywordsTech, 'TechKeywords');
        //listKeywordsConstruct,listKeywordsUpgrade
		// writeObjectListToCacheFile(listRoomConfigs, 'RoomConfigs');
		writeObjectListToCacheFile(listRoomFuncs, 'RoomFuncs');
		writeObjectListToCacheFile(listRoomResources, 'RoomResources');
		writeObjectListToCacheFile(listTechActionTypes, 'TechActionTypes');
		writeObjectListToCacheFile(listPutDownSounds, 'PutDownSounds');

		// update file timestamp

		for i:=0 to masterList.count-1 do begin
			curFileName := masterList[i];
			if(FileExists(DataPath+curFileName)) then begin
				realFileAge := FileAge(DataPath+curFileName);
				currentCacheFile.O['files'].O[curFileName].I['timestamp'] := realFileAge;
			end;
		end;

		// this stays
		writeStringList(listModels, 	currentCacheFile.O['assets'].A['ActivatorModels']);
		writeStringList(listModelsMisc, currentCacheFile.O['assets'].A['MiscModels']);

		saveCacheFile();
	end;

    procedure saveCacheFile();
    begin
        currentCacheFile.SaveToFile(cacheFile, false);
    end;

    function joinLines(l: TStringList; separator: string): string;
	var
		i: integer;
	begin
		Result := '';

		for i:=0 to l.count-1 do begin
            if(i > 0) then begin
                Result := Result + separator + l[i];
            end else begin
                Result := l[i];
            end;
			//Result := Result + l[i];
		end;
	end;

	function concatLines(l: TStringList): string;
	var
		i: integer;
	begin
		Result := '';

		for i:=0 to l.count-1 do begin
			Result := Result + l[i];
		end;
	end;

	procedure readObjectList(targetList: TStringList; sourceJson: TJsonObject);
	var
		i: integer;
		curFile: IInterface;
		curFileName: string;
		curSubJson: TJsonArray;
	begin
		for i:=0 to sourceJson.count-1 do begin
			curFileName := sourceJson.names[i];
			curFile := FindFile(curFileName);
			if(not assigned(curFile)) then begin
				AddMessage('Couldn''t find file '+curFileName);
				continue;
			end;
			curSubJson := sourceJson.A[curFileName];
			readFileDependentObjectList(curFile, targetList, curSubJson);
		end;
	end;

	procedure readFileDependentObjectList(forFile: IInterface; targetList: TStringList; sourceJson: TJsonObject);
	var
		j: integer;
		curObj: IInterface;
		curHexId, curCaption: string;
		curFormId: cardinal;
		objectEntry: TJsonObject;
	begin

		for j := 0 to sourceJson.count-1 do begin
			curCaption := sourceJson.names[j];
			curHexId := sourceJson[curCaption];

			curFormId := StrToInt('$' + curHexId);
			curObj := WinningOverrideOrSelf(getFormByFileAndFormID(forFile, curFormId));
			if(assigned(curObj)) then begin
                //AddMessage('Adding Obj: '+curCaption+' -> '+FullPath(curObj)+', got it from '+GetFileName(forFile)+' 0x'+IntToHex(curFormId, 8)//);
				addObjectDupIgnore(targetList, curCaption, curObj);
			end;
		end;
	end;

	procedure readStringList(targetList: TStringList; sourceJson: TJsonArray);
	var
		i: integer;
		curObj, curFile: IInterface;
		curFileName: string;
		curFormId: cardinal;
	begin
		for i:=0 to sourceJson.count-1 do begin
			targetList.add(sourceJson.S[i]);
		end;
	end;

	{
		Loads stuff from the cache file which requires a certain HQ into the relevant stringlists
	}
	procedure loadHqDependentFormsIntoLists(forFiles: TStringList; hq: IInterface);
	var
		listData: TStringList;

		i, j, eqPos: integer;
		curStr, formIdPart, fileNamePart, hqKey, curFileName: string;
		curFormId: cardinal;
		curObj, base, curFileObj: IInterface;
		hqContainer, currentHqObj, filesContainer, fileContainer, fileHqContainer: TJsonObject;
		realFileAge: integer;
	begin
		hqKey := FormToAbsStr(hq);//hqRef

		filesContainer := currentCacheFile.O['files'];
		for i:=0 to forFiles.count-1 do begin
			curFileName := forFiles[i];
			curFileObj  := ObjectToElement(forFiles.Objects[i]);

			fileContainer := filesContainer.O[curFileName];

			// complex stuff
			fileHqContainer := fileContainer.O['HQData'];
			currentHqObj := fileHqContainer.O[hqKey];

			readFileDependentObjectList(curFileObj, listDepartmentObjects, currentHqObj.O['Departments']);
			readFileDependentObjectList(curFileObj, listActionGroups, 	   currentHqObj.O['ActionGroups']);
			readFileDependentObjectList(curFileObj, listRoomConfigs, 	   currentHqObj.O['RoomConfigs']);

		end;
	end;

    function getFullReloadResult(forFiles: TStringList): IInterface;
    var
        i: integer;
        curFileName: string;
    begin
        Result := TJsonObject.create;
		Result.B['needModels'] := true;
        // put all the masters in
        for i:=0 to forFiles.count-1 do begin
            curFileName := forFiles[i];
            Result.A['filesToReload'].add(curFileName);
        end;
    end;

	{
		This ensures that currentCacheFile exists, and attempts to fill it
	}
	function loadListsFromCache(forFiles: TStringList): TJsonObject;
	var
		i, j, eqPos: integer;
		curStr, formIdPart, fileNamePart, hqKey, curFileName: string;
		curFormId: cardinal;
		curObj, base, curFileObj, hqRef: IInterface;
		hqContainer, currentHqObj, filesContainer, fileContainer, fileHqContainer: TJsonObject;
		realFileAge: integer;
	begin
		// Result.A['filesToReload']; // fill this with files which changed since the last time
		//currentCacheFile := TJsonObject.create();

		if(not FileExists(cacheFile)) then begin
			currentCacheFile := TJsonObject.create;

            Result := getFullReloadResult(forFiles);
			exit;
		end;

		AddMessage('Loading cache '+cacheFile);

        currentCacheFile := getFileAsJson(cacheFile);


		if(currentCacheFile = nil) then begin
			currentCacheFile := TJsonObject.create;
            Result := getFullReloadResult(forFiles);
			exit;
		end;

        if(currentCacheFile.I['version'] < cacheFileVersion) then begin
            // reset the file
            AddMessage('Cache file is outdated, regenerating');
            currentCacheFile.clear();
            Result := getFullReloadResult(forFiles);
            exit;
        end;

		Result := TJsonObject.create;
		Result.B['needModels'] := true;


		{
			Okay, try the structure like this now:
			(php-like syntax because curly braces are comment signs in pascal)
			$currentCacheFile = [
				'files' => [
					'somefile.esp' => [
						'timestamp' => // last time the file was changed
						'HQData' => [
							// HQ-dependent data goes here
							$hqKey => [
								'Departments' => // objectlist
								'ActionGroups' => // objectlist
							],
						],
						'HQs' => [
							FormToAbsStr(ref) => FormToAbsStr(manager),
						],
						'RoomShapes' // objectlist of roomshapes
						... etc

					],
				],

				'assets' => [
					// model arrays go here
				],
			];

		}

		if(currentCacheFile.S['DefaultHQ'] <> '') then begin
			SS2_HQ_WorkshopRef_GNN := AbsStrToForm(currentCacheFile.S['DefaultHQ']);
		end;



		filesContainer := currentCacheFile.O['files'];
		for i:=0 to forFiles.count-1 do begin
			curFileName := forFiles[i];

            if(nil <> forFiles.Objects[i]) then begin
                curFileObj  := ObjectToElement(forFiles.Objects[i]);
            end else begin
                // try to fetch by name
                curFileObj := FindFile(curFileName);
                if(not assigned(curFileObj)) then begin
                    AddMessage('WARNING! Required file '+curFileName+' is not loaded!');
                    // Result.A['filesToReload'].add(curFileName);
                    // fileContainer.clear();
                    continue;
                end;
            end;

			fileContainer := filesContainer.O[curFileName];
			// this shouldn't actually be possible, but sometimes happens??
			if(not FileExists(DataPath+curFileName)) then begin
				//AddMessage('File '+curFileName+' hasn''t been saved yet, no caching possible');
                Result.A['filesToReload'].add(curFileName);
                // reset the current object
				fileContainer.clear();
				continue;
			end;


			realFileAge := FileAge(DataPath+curFileName);

			if(realFileAge > fileContainer.I['timestamp']) then begin
				// file changed since
				AddMessage('File '+curFileName+' will be reloaded.');
				Result.A['filesToReload'].add(curFileName);
				// reset the current object
				fileContainer.clear();
			end else begin

				// simple stuff
				// readFileDependentObjectList(curFileObj, listHQRefs, 		fileContainer.O['HQs']);
				readFileDependentObjectList(curFileObj, listRoomShapes, 	fileContainer.O['RoomShapes']);

				readFileDependentObjectList(curFileObj, listKeywordsUpgrade,fileContainer.O['UpgradeKeywords']);
				readFileDependentObjectList(curFileObj, listKeywordsConstruct, 	fileContainer.O['ConstructKeywords']);
				readFileDependentObjectList(curFileObj, listKeywordsTech, 	fileContainer.O['TechKeywords']);
                // AddMessage('loading for '+curFileName+' '+fileContainer.O['TechKeywords'].toString());


				//readFileDependentObjectList(curFileObj, listRoomConfigs, 	fileContainer.O['RoomConfigs']);
				readFileDependentObjectList(curFileObj, listRoomFuncs, 		fileContainer.O['RoomFuncs']);
				//readFileDependentObjectList(curFileObj, listHqManagers, 	fileContainer.O['HqManagers']);
				readFileDependentObjectList(curFileObj, listRoomResources, 	fileContainer.O['RoomResources']);
				readFileDependentObjectList(curFileObj, listTechActionTypes,fileContainer.O['TechActionTypes']);
				readFileDependentObjectList(curFileObj, listPutDownSounds,fileContainer.O['PutDownSounds']);
			end;

		end;

		readStringList(listModels, 	   currentCacheFile.O['assets'].A['ActivatorModels']);
		readStringList(listModelsMisc, currentCacheFile.O['assets'].A['MiscModels']);

        // if we had to reload at least one file, also reload all models
		if (Result.A['filesToReload'].count = 0) and ((listModels.count > 0) or (listModelsMisc.count > 0)) then begin
			// seems we have enough models
			Result.B['needModels'] := false;
		end;


		AddMessage('Cache loaded');
	end;



	procedure loadForms();
	var
		i, numData: integer;
		curFile: IInterface;
		hasFormData, hasModelData: boolean;
		masterList: TStringList;
		cacheResult: TJsonObject;
		curFileName: string;
		filesToReload: TJsonArray;
	begin
		//AddMessage('Loading data for HQ '+findHqName(targetHQ)+'...');

		masterList := getMasterList(targetFile);

        // hardcode-add some files
        //masterList.add('SS2.esm');
        //masterList.add('SS2_XPAC_Chapter2.esm');

		cacheResult := loadListsFromCache(masterList);



		filesToReload := cacheResult.A['filesToReload'];


		startProgress('Loading data...', filesToReload.count+1);
		if(filesToReload.count > 0) then begin
			for i:=0 to filesToReload.count-1 do begin
				updateProgress(i);
				curFileName := filesToReload.S[i];
				// AddMessage('Reloading data from '+curFileName);
				loadFormsFromFile(FindFile(curFileName));
			end;
		end;

		loadFormsFromFile(targetFile);

		endProgress();

		if(cacheResult.B['needModels']) then begin
			loadModels();
		end;

		saveListsToCache(masterList);
		masterList.free();
		AddMessage('Data loaded.');
		cacheResult.free();

		listHQRefs := getHqList();
	end;

	procedure loadFormsForHq(hq: IInterface);
	var
		masterList: TStringList;
	begin
		masterList := getMasterList(targetFile);
		masterList.addObject(GetFileName(targetFile), targetFile);
		// for this, the cachefile should exist, and it should load the data for the specified HQ into the stringlists
		loadHqDependentFormsIntoLists(masterList, hq);

		masterList.free();
	end;

	function getHqList(): TStringList;
	var
		i, j: integer;
		filesEntry, hqList: TJsonObject;
		curFileName, curHqStr, hqName: string;
		hqRef: IInterface;
	begin
		Result := TStringList.create;

		filesEntry := currentCacheFile.O['files'];

		for i:=0 to filesEntry.count-1 do begin
			curFileName := filesEntry.names[i];
			hqList := filesEntry.O[curFileName].O['HQs'];

			for j:=0 to hqList.count-1 do begin
				curHqStr := hqList.names[j];

				hqRef := AbsStrToForm(curHqStr);
				hqName := findHqName(hqRef);

				Result.addObject(hqName, hqRef);
			end;
		end;
	end;

	function FindObjectByEdidWithError(edid: string): IInterface;
	begin
		Result := FindObjectByEdid(edid);
		if(not assigned(Result)) then begin
			AddMessage('Failed to find form '+edid);
			hasFindObjectError := true;
		end;
	end;


    // Called before processing
    // You can remove it if script doesn't require initialization code
    function Initialize: integer;
    begin
		currentCacheFile := nil;
		progressBarWindow := nil;
        Result := 0;

		if(not initSS2Lib()) then begin
			Result := 1;
			exit;
		end;
		hasFindObjectError := false;
		// records we always need
		SS2_HQ_FauxWorkshop := FindObjectByEdidWithError('SS2_HQ_FauxWorkshop'); //SS2_HQ_FauxWorkshop "Workshop" [CONT:0400379B]
		SS2_FLID_HQActions := FindObjectByEdidWithError('SS2_FLID_HQActions');
		SS2_TF_HologramGNNWorkshopTiny := FindObjectByEdidWithError('SS2C2_TF_HologramGNNWorkshopTiny');
		SS2_HQ_Action_RoomUpgrade_Template := FindObjectByEdidWithError('SS2_HQ_Action_RoomUpgrade_Template');
		SS2_HQRoomLayout_Template := FindObjectByEdidWithError('SS2_HQRoomLayout_Template');

        CobjRoomConstruction_Template := FindObjectByEdidWithError('SS2C2_co_HQBuildableAction_GNN_RoomConstruction_Template');
        CobjRoomUpgrade_Template      := FindObjectByEdidWithError('SS2C2_co_HQBuildableAction_GNN_RoomUpgrade_Template');
        // SS2C2_co_HQBuildableAction_GNN_RoomConstruction_Template or SS2C2_co_HQBuildableAction_GNN_RoomUpgrade_Template


		WorkshopItemKeyword := FindObjectByEdidWithError('WorkshopItemKeyword');

		SS2_HQGNN_Action_AssignRoomConfig_Template := FindObjectByEdidWithError('SS2_HQ_Action_RoomConfig_Template');

		SS2_HQ_RoomSlot_Template := FindObjectByEdidWithError('SS2_HQ_RoomSlot_Template');
		SS2_HQ_RoomSlot_Template_GNN := FindObjectByEdidWithError('SS2C2_HQ_RoomSlot_Template_GNN');
		SS2_HQBuildableAction_Template := FindObjectByEdidWithError('SS2_HQBuildableAction_Template');
        //LayoutDescriptionTemplate := FindObjectByEdidWithError('SS2_Name_Dog');
		SS2_HQ_RoomSlot_Template_GNN := FindObjectByEdidWithError('SS2C2_HQ_RoomSlot_Template_GNN');

		SS2_VirtualResourceCategory_Scrap 			  := FindObjectByEdidWithError('SS2_VirtualResourceCategory_Scrap');
		SS2_VirtualResourceCategory_Supplies 		  := FindObjectByEdidWithError('SS2_VirtualResourceCategory_Supplies');
		SS2_VirtualResourceCategory_RareMaterials 	  := FindObjectByEdidWithError('SS2_VirtualResourceCategory_RareMaterials');
		SS2_VirtualResourceCategory_OrganicMaterials  := FindObjectByEdidWithError('SS2_VirtualResourceCategory_OrganicMaterials');
		SS2_VirtualResourceCategory_MachineParts 	  := FindObjectByEdidWithError('SS2_VirtualResourceCategory_MachineParts');
		SS2_VirtualResourceCategory_BuildingMaterials := FindObjectByEdidWithError('SS2_VirtualResourceCategory_BuildingMaterials');
		SS2_VirtualResource_SuppliesCategory_Ammo := FindObjectByEdidWithError('SS2_VirtualResource_SuppliesCategory_Ammo');
		SS2_VirtualResource_SuppliesCategory_Armor := FindObjectByEdidWithError('SS2_VirtualResource_SuppliesCategory_Armor');
		SS2_VirtualResource_SuppliesCategory_Chems := FindObjectByEdidWithError('SS2_VirtualResource_SuppliesCategory_Chems');
		SS2_VirtualResource_SuppliesCategory_WeaponParts := FindObjectByEdidWithError('SS2_VirtualResource_SuppliesCategory_WeaponParts');
		SS2_UsageRequirements_PerformanceSettingOn_Clutter := FindObjectByEdidWithError('SS2_UsageRequirements_PerformanceSettingOn_Clutter');

		SS2_c_HQ_DailyLimiter_Scrap             := FindObjectByEdidWithError('SS2_c_HQ_DailyLimiter_Scrap');
		SS2_c_HQ_DailyLimiter_Supplies          := FindObjectByEdidWithError('SS2_c_HQ_DailyLimiter_Supplies');
		SS2_Tag_HQ_RoomIsClean                  := FindObjectByEdidWithError('SS2_Tag_HQ_RoomIsClean');
        SS2_Tag_HQ_ActionType_RoomConstruction  := FindObjectByEdidWithError('SS2_Tag_HQ_ActionType_RoomConstruction');
        SS2_Tag_HQ_ActionType_RoomUpgrade       := FindObjectByEdidWithError('SS2_Tag_HQ_ActionType_RoomUpgrade');

        SS2_SFX_HQProjectType_Administration_Decorate   := FindObjectByEdidWithError('SS2_SFX_HQProjectType_Administration_Decorate');
        SS2_WorkshopMenu_HQ_Administration_Decorate     := FindObjectByEdidWithError('SS2_WorkshopMenu_HQ_Administration_Decorate');

        defaultUpgradeKw        := FindObjectByEdidWithError('SS2_WorkshopMenu_HQ_Engineering_Upgrades_Other');
        defaultConstructionKw   := FindObjectByEdidWithError('SS2_WorkshopMenu_HQ_Facilities_Construction_Other');

		if(hasFindObjectError) then begin
			Result := 1;
			exit;
		end;

		if(not assigned(SS2_HQ_FauxWorkshop)) then begin
			AddMessage('no SS2_HQ_FauxWorkshop');
			Result := 1;
			exit;
		end;

		progressBarStack := TJsonArray.create;

		listHQRefs := nil;
		listRoomShapes := TStringList.create;
        listKeywordsConstruct := TStringList.create;
        listKeywordsUpgrade := TStringList.create;
        listKeywordsTech := TStringList.create;
		listDepartmentObjects := TStringList.create;
		listActionGroups := TStringList.create;
		listRoomFuncs := TStringList.create;
		//listHqManagers := TStringList.create;
		listModels := TStringList.create;
		listModelsMisc := TStringList.create;
		listRoomResources := TStringList.create;
		listTechActionTypes := TStringList.create;
		listPutDownSounds := TStringList.create;
		listRoomConfigs := TStringList.create;

		resourceLookupTable := TJsonObject.create;
		edidLookupCache     := TStringList.create;


        // scriptExtendsCache.OwnsObjects := true; // another thing xedit doesn't support

		listRoomFuncs.Sorted := true;
		listRoomResources.Sorted := true;
		listTechActionTypes.Sorted := true;
		listPutDownSounds.Sorted := true;
		listModels.Sorted := true;
		listModelsMisc.Sorted := true;
		listRoomConfigs.Sorted := true;
		listKeywordsTech.Sorted := true;
		listDepartmentObjects.Sorted := true;
		listActionGroups.Sorted := true;
		listRoomShapes.Sorted := true;

		//listHQRefs.Duplicates := dupIgnore;
		listRoomShapes.Duplicates := dupIgnore;
        listKeywordsConstruct.Duplicates := dupIgnore;
        listKeywordsUpgrade.Duplicates := dupIgnore;
        listKeywordsTech.Duplicates := dupIgnore;
		listDepartmentObjects.Duplicates := dupIgnore;
		listActionGroups.Duplicates := dupIgnore;
		listRoomConfigs.Duplicates := dupIgnore;
		listRoomFuncs.Duplicates := dupIgnore;
		//listHqManagers.Duplicates := dupIgnore;
		listModels.Duplicates := dupIgnore;
		listModelsMisc.Duplicates := dupIgnore;
		listRoomResources.Duplicates := dupIgnore;
		listTechActionTypes.Duplicates := dupIgnore;
		listPutDownSounds.Duplicates := dupIgnore;

    end;

    // called for every record selected in xEdit
    function Process(e: IInterface): integer;
    begin
        Result := 0;

		if(not assigned(targetElem)) then begin
			targetElem := e;
			targetFile := GetFile(e);
		end else begin
            AddMessage('Please run this on exactly one item. Try the file header if you don''t want to update anything.');
            Result := 1;
            exit;
        end;
    end;

	procedure updateRoomUpgrade1OkBtn(sender: TObject);
	var
		frm: TForm;
		btnOk: TButton;
		selectRoomConfig: TComboBox;
	begin
		frm := findComponentParentWindow(sender);
		btnOk := TButton(frm.FindComponent('btnOk'));

        selectRoomConfig := TComboBox(frm.FindComponent('selectRoomConfig'));

		btnOk.enabled := (selectRoomConfig.ItemIndex >= 0);
	end;

	procedure updateRoomConfigOkBtn(sender: TObject);
	var
		inputName, inputPrefix: TEdit;
		btnOk: TButton;
		selectRoomShape, selectActionGroup: TComboBox;
		frm: TForm;
    begin
		frm := findComponentParentWindow(sender);
        inputName := TEdit(frm.FindComponent('inputName'));
        inputPrefix := TEdit(frm.FindComponent('inputPrefix'));
        //selectMainDep := TComboBox(frm.FindComponent('selectMainDep'));
        selectRoomShape := TComboBox(frm.FindComponent('selectRoomShape'));
        selectActionGroup := TComboBox(frm.FindComponent('selectActionGroup'));

		btnOk := TButton(frm.FindComponent('btnOk'));

		if (trim(inputName.text) <> '') and (trim(inputPrefix.text) <> '') and (selectActionGroup.ItemIndex >= 0) and ((selectRoomShape.ItemIndex >= 0) or (trim(selectRoomShape.text) <> '')) then begin
			btnOk.enabled := true;
		end else begin
			btnOk.enabled := false;
		end;

    end;

	procedure addUpgradeSlotHandler(Sender: TObject);
	var
		listSlots: TListBox;
		frm: TForm;
		newString: string;
        slotsGroup: TGroupBox;
	begin
		frm := sender.parent;
        listSlots := TListBox(frm.FindComponent('listSlots'));

		if(InputQuery('Room Config', 'Input upgrade slot name', newString)) then begin
			newString := cleanStringForEditorID(trim(newString));
			if(newString <> '') then begin
				if(listSlots.Items.indexOf(newString) < 0) then begin
					listSlots.Items.add(newString);
				end else begin
					AddMessage('"'+newString+'" already exists');
				end;
			end else begin
				AddMessage('Invalid string given');
			end;
		end;
	end;

	procedure remUpgradeSlotHandler(Sender: TObject);
	var
		listSlots: TListBox;
		frm: TForm;
        slotsGroup: TGroupBox;
	begin
        if(listSlots = nil) then begin
            slotsGroup := TGroupBox (sender.parent.FindComponent('slotsGroup'));
			listSlots := TListBox(slotsGroup.FindComponent('listSlots'));
        end;

		frm := sender.parent;
        listSlots := TListBox(frm.FindComponent('listSlots'));

        deleteSelectedBoxItems(listSlots);
	end;

	function getRefLocation(ref: IInterface): IInterface;
	var
		cell: IInterface;
	begin
		cell := PathLinksTo(e, 'Cell');
		if(not assigned(cell)) then begin
			exit;
		end;

		Result := PathLinksTo(cell, 'XLCN');
	end;

    procedure fixEditorID(form: IInterface);
    var
        curEdid, newEdid: string;
    begin
        curEdid := EditorID(form);
        newEdid := shortenEdid(curEdid);
        if(curEdid <> newEdid) then begin
            SetElementEditValues(form, 'EDID', newEdid);
        end;
    end;

	function getUpgradeSlot(existingMisc: IInterface; roomShape, roomName, slotName: string; forHq: IInterface): IInterface;
	var
		edidMisc, edidKw: string;
		slotMisc, slotKw, miscScript: IInterface;
	begin
		edidMisc := shortenEdid(globalNewFormPrefix+'HQ_RoomSlot_'+roomShape+'_'+roomName+'_'+slotName);
		edidKw   := shortenEdid(globalNewFormPrefix+'Tag_RoomSlot_'+roomShape+'_'+roomName+'_'+slotName);
		// MISC: SS2_HQ_RoomSlot_GNNLowerSouthwestNookShape_CommonArea_Base
		//       SS2_HQ_RoomSlot_<room shape>_<room name>_<slot name>

		// SS2_Tag_RoomSlot_GNNLowerSouthwestNookShape_CommonArea_Base [KYWD:0B00A3AB]
		// SS2_Tag_RoomSlot_<room shape>_<room name>_<slot name> [KYWD:0B00A3AB]


		if(not assigned(existingMisc)) then begin
			slotKw := getCopyOfTemplateOA(targetFile, keywordTemplate, edidKw);
			if(EditorID(forHq) = 'SS2_HQ_WorkshopRef_GNN') then begin
				slotMisc := getCopyOfTemplateOA(targetFile, SS2_HQ_RoomSlot_Template_GNN, edidMisc);
				miscScript := getScript(slotMisc, 'SimSettlementsV2:HQ:Library:MiscObjects:RequirementTypes:HQRoomUpgradeSlot_GNN');
			end else begin
				slotMisc := getCopyOfTemplateOA(targetFile, SS2_HQ_RoomSlot_Template, edidMisc);
				miscScript := getScript(slotMisc, 'simsettlementsv2:hq:library:miscobjects:requirementtypes:hqroomupgradeslot');
				setScriptProp(miscScript, 'HQLocation', getRefLocation(forHq));
			end;
			setScriptProp(miscScript, 'UpgradeSlotKeyword', slotKw);
		end else begin
            existingMisc := WinningOverrideOrSelf(existingMisc);
			slotMisc := existingMisc;
			miscScript := getScript(slotMisc, 'SimSettlementsV2:HQ:Library:MiscObjects:RequirementTypes:HQRoomUpgradeSlot_GNN');
			if(not assigned(miscScript)) then begin
				miscScript := getScript(slotMisc, 'simsettlementsv2:hq:library:miscobjects:requirementtypes:hqroomupgradeslot');
			end;
			slotKw := getScriptProp(miscScript, 'UpgradeSlotKeyword');

            // fix: shorten the EDIDs of these two
            fixEditorID(slotMisc);
            fixEditorID(slotKw);
		end;

		SetElementEditValues(slotMisc, 'FULL', slotName);
		SetElementEditValues(slotKw, 'FULL', slotName);

		Result := slotMisc;
	end;

	function createHqRoomConfig(
        existingElem: IInterface;
        forHq: IInterface;
        roomName: string;
        roomShapeKw: IInterface;
        roomShapeKwEdid: string;
        actionGroup: IInterface;
        primaryDepartment: IInterface;
        UpgradeSlots: TStringList
    ): IInterface;
	var
		configMisc, configMiscScript, roomConfigKw, roomUpgradeSlots, curSlotMisc: IInterface;
		kwBase, curSlotName, configMiscEdid, roomNameSpaceless, roomConfigKeywordEdid: string;
		oldRoomShapeKw, oldUpgradeMisc, roomConfigKeyword: IInterface;
		i: integer;
	begin

		roomNameSpaceless := cleanStringForEditorID(roomName);

		if (assigned(roomShapeKw)) then begin
			roomShapeKwEdid := EditorID(roomShapeKw);
		end else begin
			// find/make KW
			roomShapeKw := getCopyOfTemplateOA(targetFile, keywordTemplate, roomShapeKwEdid);
		end;

		kwBase := getRoomShapeUniquePart(roomShapeKwEdid);
		if(kwBase = '') then begin
			kwBase := roomShapeKwEdid;
		end;

        // roomConfigKw := nil;

        roomShapeKw := WinningOverrideOrSelf(roomShapeKw);
        actionGroup := WinningOverrideOrSelf(actionGroup);
        primaryDepartment := WinningOverrideOrSelf(primaryDepartment);

		if(not assigned(existingElem)) then begin
			configMiscEdid := generateEdid('HQ' + findHqNameShort(forHq)+'_Action_AssignRoomConfig_', kwBase+'_'+roomNameSpaceless);
			configMisc := getCopyOfTemplateOA(targetFile, SS2_HQGNN_Action_AssignRoomConfig_Template, configMiscEdid);
			addKeywordByPath(configMisc, roomShapeKw, 'KWDA');

			roomConfigKeywordEdid := generateEdid('Tag_RoomConfig_', kwBase+'_'+roomNameSpaceless);
			roomConfigKeyword := getCopyOfTemplateOA(targetFile, keywordTemplate, roomConfigKeywordEdid);
		end else begin
            existingElem := WinningOverrideOrSelf(existingElem);
			configMisc := getOrCreateElementOverride(existingElem, targetFile);
			// try to remove the current room shape KW
			oldRoomShapeKw := findKeywordByList(existingElem, listRoomShapes);
			if(not FormsEqual(oldRoomShapeKw, roomShapeKw)) then begin
				removeKeywordByPath(configMisc, oldRoomShapeKw, 'KWDA');
				addKeywordByPath(configMisc, roomShapeKw, 'KWDA');
			end;
		end;


		SetElementEditValues(configMisc, 'FULL', roomName);

		configMiscScript := getScript(configMisc, 'SimSettlementsV2:HQ:Library:MiscObjects:RequirementTypes:ActionTypes:HQRoomConfig');
		setScriptProp(configMiscScript, 'ActionGroup', actionGroup);

        if(assigned(primaryDepartment)) then begin
            setScriptProp(configMiscScript, 'PrimaryDepartment', primaryDepartment);
        end else begin
            deleteScriptProp(configMiscScript, 'PrimaryDepartment');
        end;



		//roomConfigKw := getCopyOfTemplateOA(targetFile, keywordTemplate, globalNewFormPrefix+'Tag_RoomConfig_'+kwBase+'_'+roomNameSpaceless);

		setScriptProp(configMiscScript, 'RoomShapeKeyword', roomShapeKw);

		if(assigned(roomConfigKeyword)) then begin
			setScriptProp(configMiscScript, 'RoomConfigKeyword', roomConfigKeyword);
		end;

		roomUpgradeSlots := getOrCreateScriptProp(configMiscScript, 'RoomUpgradeSlots', 'Array of Object');
		clearProperty(roomUpgradeSlots);
		// RoomUpgradeSlots array of obj, generated from UpgradeSlots
		for i:=0 to UpgradeSlots.count-1 do begin
			curSlotName := cleanStringForEditorID(UpgradeSlots[i]);

			oldUpgradeMisc := WinningOverrideOrSelf(ObjectToElement(UpgradeSlots.Objects[i]));

			curSlotMisc := getUpgradeSlot(oldUpgradeMisc, kwBase, roomNameSpaceless, curSlotName, forHq);
			appendObjectToProperty(roomUpgradeSlots, curSlotMisc);
		end;

		Result := configMisc;
	end;

	function findKeywordByList(e: IInterface; possibleKeywords: TStringList): IInterface;
	var
		kwda, curKW: IInterface;
		i: integer;
		curEdid: string;
	begin
        e := WinningOverrideOrSelf(e);
		kwda := ElementByPath(e, 'KWDA');

		Result := nil;

		for i := 0 to ElementCount(kwda)-1 do begin
            curKW := LinksTo(ElementByIndex(kwda, i));
			curEdid := EditorID(curKW);

			if(possibleKeywords.indexOf(curEdid) >= 0) then begin
				Result := curKW;
				exit;
			end;
        end;
	end;

	procedure setItemIndexByValue(dropDown: TComboBox; value: string);
	var
		index: integer;
	begin
		index := dropDown.Items.indexOf(value);
		if(index >= 0) then begin
			dropDown.ItemIndex := index;
		//end else begin
		//	dropDown.ItemIndex := -1;
		end;
	end;

	procedure setItemIndexByForm(dropDown: TComboBox; form: IInterface);
	var
		i, index, prevIndex: integer;
		curForm: IInterface;
	begin
        if(not assigned(form)) then begin
            exit;
        end;

		for i:=0 to dropDown.Items.count-1 do begin

			if(dropDown.Items.Objects[i] <> nil) then begin
				curForm := ObjectToElement(dropDown.Items.Objects[i]);

				if(FormsEqual(curForm, form)) then begin
					dropDown.ItemIndex := i;
					exit;
				end;
			end;
		end;
        AddMessage('setItemIndexByForm failed to find');

		//dropDown.ItemIndex := prevIndex;
	end;



	function getRoomUpgradeSlots(forHq, roomConfig: IInterface): TStringList;
	var
		configScript, RoomUpgradeSlots, curSlot: IInterface;
		i, j: integer;
		slotName, curFileName, hqKey, roomConfigKey, formIdStr: string;
        fileJson, slotJson: TJsonObject;
	begin
		Result := TStringList.create();

        hqKey := FormToAbsStr(forHq);
        roomConfigKey := FormToAbsStr(roomConfig);

        // load from cache
        fileJson := currentCacheFile.O['files'];
        for i:=0 to fileJson.count-1 do begin
            curFileName := fileJson.names[i];
            slotJson := fileJson.O[curFileName].O['HQData'].O[hqKey].O['RoomConfigSlots'].O[roomConfigKey];

            for j:=0 to slotJson.count-1 do begin
                slotName := slotJson.names[j];
                formIdStr := slotJson.S[slotName];
                curSlot := getFormByFilenameAndFormID(curFileName, StrToInt('$'+formIdStr));

                addObjectDupIgnore(Result, slotName, curSlot);
            end;
        end;

	end;

	function prependDummyEntry(list: TStringList; title: string): TStringList;
	var
		i: integer;
	begin
		Result := TStringList.create();
		Result.add(title);

		for i:=0 to list.count-1 do begin
			addObjectDupIgnore(Result, list[i], ObjectToElement(list.Objects[i]));
            //Result.AddObject(list[i], list.Objects[i]);
		end;
	end;

	function prependNoneEntry(list: TStringList): TStringList;
	begin
		Result := prependDummyEntry(list, '- NONE -');
	end;

    procedure deserializeSlotJsonIntoList(jsonStr: string; list: TStringList);
    var
        jsonArray: TJsonArray;
        jsonMain, jsonTemp, newEntry: TJsonObject;
        i, count, index: integer;
        slot: IInterface;
        curName: string;
    begin
        //jsonArray := TJsonArray.create;
        jsonMain := TJSONObject.Parse(jsonStr);
        if(jsonMain = nil) then begin
            exit;
        end;

        if(jsonMain.S['type'] <> 'slots') then begin
            jsonMain.free();
            exit;
        end;

        jsonArray := jsonMain.A['data'];
        if(jsonArray = nil) then begin
            AddMessage('failed parsing '+jsonStr);
            exit;
        end;

        for i:=0 to jsonArray.count-1 do begin
            jsonTemp := jsonArray.O[i];

            curName := jsonTemp.S['name'];
            if(jsonTemp.S['form'] <> '') then begin
                slot := AbsStrToForm(jsonTemp.S['form']);
            end;

            if(list.indexOf(curName) < 0) then begin
                if(assigned(slot)) then begin
                    list.AddObject(curName, slot);
                end else begin
                    list.add(curName);
                end;
			end;
        end;
        jsonMain.free();
    end;

    function serializeSlotListToJson(list: TStringList): string;
    var
        jsonArr: TJsonArray;
        jsonMain, jsonTemp, existingEntry: TJsonObject;
        i, resIndex: integer;
        slot: IInterface;
    begin
        jsonMain := TJsonObject.create();
        jsonMain.S['type'] := 'slots';

        jsonArr := jsonMain.A['data'];

        for i:=0 to list.count-1 do begin
            jsonTemp := jsonArr.addObject();
            jsonTemp.S['name'] := list[i];

            if(list.Objects[i] <> nil) then begin
                slot := ObjectToElement(list.Objects[i]);
                jsonTemp.S['form'] := FormToAbsStr(func);
            end;
        end;

        Result := jsonMain.toString();
        jsonMain.free();
    end;


    function serializeRoomFuncListToJson(list: TStringList): string;
    var
        jsonArr: TJsonArray;
        jsonMain, jsonTemp, existingEntry: TJsonObject;
        i, resIndex: integer;
        func: IInterface;
    begin
        jsonMain := TJsonObject.create();
        jsonMain.S['type'] := 'roomfuncs';

        jsonArr := jsonMain.A['data'];

        for i:=0 to list.count-1 do begin
            func := ObjectToElement(list.Objects[i]);

            jsonTemp := jsonArr.addObject();
            jsonTemp.S['form'] := FormToAbsStr(func);
        end;

        Result := jsonMain.toString();
        jsonMain.free();
    end;

    function hasLayout(layoutList: TStringList; newEntryDisplay: string; newEntryJson: TJsonObject): boolean;
    var
        j: integer;
        checkEntry: TJsonObject;
    begin
        for j:=0 to layoutList.count-1 do begin
            checkEntry := TJsonObject(layoutList.Objects[j]);
            if (checkEntry.S['path'] <> '') and (checkEntry.S['path'] = newEntryJson.S['path']) then begin
                Result := true;
                exit;
            end;

            if (checkEntry.S['existing'] <> '') and (checkEntry.S['existing'] = newEntryJson.S['existing']) then begin
                Result := true;
                exit;
            end;

        end;

        Result := false;
    end;

    procedure deserializeLayoutJsonIntoList(jsonStr: string; list: TStringList);
    var
        jsonArray: TJsonArray;
        jsonMain, jsonTemp, newEntry, checkEntry: TJsonObject;
        i, j, count, resIndex: integer;
        slot, existing: IInterface;
        displayName: string;
        canInsert: boolean;
    begin
        //jsonArray := TJsonArray.create;
        jsonMain := TJSONObject.Parse(jsonStr);
        if(jsonMain = nil) then begin
            exit;
        end;

        if(jsonMain.S['type'] <> 'layouts') then begin
            jsonMain.free();
            exit;
        end;

        jsonArray := jsonMain.A['data'];
        if(jsonArray = nil) then begin
            AddMessage('failed parsing '+jsonStr);
            exit;
        end;

        for i:=0 to jsonArray.count-1 do begin
            jsonTemp := jsonArray.O[i];
            newEntry := TJsonObject.create;
            newEntry.S['name'] := jsonTemp.S['name'];
            newEntry.S['path'] := jsonTemp.S['path'];

            existing := nil;
            slot := AbsStrToForm(jsonTemp.S['slot']);
            if(jsonTemp.S['existing'] <> '') then begin
                existing := AbsStrToForm(jsonTemp.S['existing']);
                newEntry.S['existing'] := FormToAbsStr(existing);
            end;

            newEntry.S['slot'] := FormToAbsStr(slot);
            displayName := '';

            // now, generate the name, and make sure it's not a duplicate
            if(assigned(existing)) then begin
                if(newEntry.S['path'] <> '') then begin
                    displayName := getLayoutDisplayName(newEntry.S['name'], newEntry.S['path'], slot) + ' *';
                end else begin
                    displayName := getLayoutDisplayName(newEntry.S['name'], EditorID(existing), slot);
                end;
            end else begin
                displayName := getLayoutDisplayName(newEntry.S['name'], newEntry.S['path'], slot);
            end;

            canInsert := not hasLayout(list, displayName, newEntry);

            if(canInsert) then begin
                list.addObject(displayName, newEntry);
            end else begin
                newEntry.free();
            end;

        end;
        jsonMain.free();
    end;

    function serializeLayoutListToJson(list: TStringList): string;
    var
        jsonArr: TJsonArray;
        jsonMain, jsonTemp, existingEntry: TJsonObject;
        i, resIndex: integer;
        slot, existing: IInterface;
    begin
        jsonMain := TJsonObject.create();
        jsonMain.S['type'] := 'layouts';

        jsonArr := jsonMain.A['data'];

        for i:=0 to list.count-1 do begin
            existingEntry := TJsonObject(list.Objects[i]);
            // AddMessage('Serialize #'+IntToStr(i)+' '+existingEntry.S['slot']);
            slot := AbsStrToForm(existingEntry.S['slot']);

            jsonTemp := jsonArr.addObject();
            jsonTemp.S['name'] := existingEntry.S['name'];
            jsonTemp.S['path'] := existingEntry.S['path'];
            jsonTemp.S['slot'] := FormToAbsStr(slot);

            if(existingEntry.S['existing'] <> '') then begin
                existing := AbsStrToForm(existingEntry.S['existing']);
                jsonTemp.S['existing'] := FormToAbsStr(existing);
            end;
        end;

        Result := jsonMain.toString();
        jsonMain.free();
    end;

    function serializeResourceListToJson(list: TStringList): string;
    var
        jsonArr: TJsonArray;
        jsonMain, jsonTemp, existingEntry: TJsonObject;
        i, resIndex: integer;
        res: IInterface;
    begin
        jsonMain := TJsonObject.create();
        jsonMain.S['type'] := 'resources';

        jsonArr := jsonMain.A['data'];

        // jsonArr := TJsonArray.create;

        for i:=0 to list.count-1 do begin
            existingEntry := TJsonObject(list.Objects[i]);

            jsonTemp := jsonArr.addObject();
            jsonTemp.I['count'] := existingEntry.I['count'];

            resIndex  := existingEntry.I['index'];
            res := ObjectToElement(listRoomResources.Objects[resIndex]);

            jsonTemp.S['form'] := FormToAbsStr(res);
            //resIndex := indexOfElement(listRoomResources, curResObject);
        end;

        Result := jsonMain.toString();
        jsonMain.free();
    end;

    function hasClipboardData(dataKey: string): boolean;
    var
        jsonArray: TJsonArray;
        jsonMain, jsonTemp, newEntry: TJsonObject;
        i, count, resIndex: integer;
        res: IInterface;
        jsonStr: string;
    begin
        //AddMessage('do we have? '+dataKey);
        jsonStr := getFakeClipboardText();
        if(jsonStr = '') then begin
            exit;
        end;
        jsonMain := TJSONObject.Parse(jsonStr);
        if(jsonMain = nil) then begin
            Result := false;
            jsonMain.free();
            exit;
        end;

        if(jsonMain.S['type'] = dataKey) then begin
            Result := true;
        end else begin
            Result := false;
        end;
        jsonMain.free();
    end;

    procedure deserializeRoomFuncsJsonIntoList(jsonStr: string; list: TStringList);
    var
        jsonArray: TJsonArray;
        jsonMain, jsonTemp, newEntry: TJsonObject;
        i, count, index: integer;
        func: IInterface;
        curName: string;
    begin
        //jsonArray := TJsonArray.create;
        jsonMain := TJSONObject.Parse(jsonStr);
        if(jsonMain = nil) then begin
            exit;
        end;

        if(jsonMain.S['type'] <> 'roomfuncs') then begin
            jsonMain.free();
            exit;
        end;

        jsonArray := jsonMain.A['data'];
        if(jsonArray = nil) then begin
            AddMessage('failed parsing '+jsonStr);
            exit;
        end;

        for i:=0 to jsonArray.count-1 do begin
            jsonTemp := jsonArray.O[i];
            func := AbsStrToForm(jsonTemp.S['form']);
            if (not assigned(func)) then begin
                continue;
            end;

            index := indexOfElement(listRoomFuncs, func);
            if(index < 0) then begin
                continue;
            end;
            curName := listRoomFuncs[index];

            if(list.indexOf(curName) < 0) then begin
				list.AddObject(curName, func);
			end;

        end;
        jsonMain.free();
    end;

    procedure deserializeResourceJsonIntoList(jsonStr: string; list: TStringList);
    var
        jsonArray: TJsonArray;
        jsonMain, jsonTemp, newEntry: TJsonObject;
        i, count, resIndex: integer;
        res: IInterface;
    begin
        //jsonArray := TJsonArray.create;
        jsonMain := TJSONObject.Parse(jsonStr);
        if(jsonMain = nil) then begin
            exit;
        end;

        if(jsonMain.S['type'] <> 'resources') then begin
            jsonMain.free();
            exit;
        end;

        jsonArray := jsonMain.A['data'];
        if(jsonArray = nil) then begin
            AddMessage('failed parsing '+jsonStr);
            exit;
        end;

        for i:=0 to jsonArray.count-1 do begin
            jsonTemp := jsonArray.O[i];
            res := AbsStrToForm(jsonTemp.S['form']);
            count := jsonTemp.I['count'];
            resIndex := indexOfElement(listRoomResources, res);

            addResourceToList(resIndex, count, list);
        end;
        jsonMain.free();
    end;

    function getResourceIndex(text: string): integer;
    begin
        Result := listRoomResources.indexOf(text);
    end;

    procedure addResourceToList(resIndex, cnt: Integer; list: TStringList);
	var
		nameBase: string;
		//resForm: IInterface;
		resourceData: TJsonObject;
		i, newCnt: integer;
	begin
		if(cnt <= 0) then begin
			exit;
		end;

		nameBase := listRoomResources[resIndex];
		//resForm := listRoomResources.Objects[resIndex];

		// try to find existing
		for i:=0 to list.count-1 do begin
			resourceData := list.Objects[i];
			if (resourceData.I['index'] = resIndex) then begin
				newCnt := resourceData.I['count']+cnt;
				resourceData.I['count'] := newCnt;
				list[i] := IntToStr(newCnt) + ' x ' + nameBase;
				exit;
			end;
		end;

		resourceData := TJsonObject.create();

		resourceData.I['index'] := resIndex;
		resourceData.I['count'] := cnt;

		list.AddObject(IntToStr(cnt)+' x '+nameBase, resourceData);
	end;

	procedure addResourceToListBox(resIndex, cnt: Integer; box: TListBox);
	begin
		addResourceToList(resIndex, cnt, box.Items);
	end;

	procedure freeStringListObjects(list: TStringList);
	var
		i: integer;
	begin
		for i:=0 to list.count-1 do begin
			list.Objects[i].free();
		end;
	end;

	procedure editResourceHandler(Sender: TObject);
	var
        frm: TForm;
		btnOk, btnCancel: TButton;
		inputName: TEdit;
		resultCode, nr, resIndex: integer;
		resourceBox: TListBox;
		resourceData: TJsonObject;
		nameBase: string;
	begin
		resourceBox := TListBox(sender.parent.FindComponent('resourceBox'));
		if(resourceBox.ItemIndex < 0) then begin
			exit;
		end;

		resourceData := resourceBox.Items.Objects[resourceBox.ItemIndex];

		frm := CreateDialog('Edit Resource', 300, 130);
		CreateLabel(frm, 10, 10, 'Input new resource amount');

		inputName := CreateInput(frm, 10, 28, resourceData.I['count']);
		inputName.Width := 50;

		resIndex := resourceData.I['index'];
		nameBase := listRoomResources[resIndex];
		CreateLabel(frm, 66, 30, nameBase);


		btnOk := CreateButton(frm, 50, 64, 'OK');
		btnOk.ModalResult := mrYes;
		btnOk.Name := 'btnOk';
		btnOk.Default := true;

		btnCancel := CreateButton(frm, 160, 64, 'Cancel');
		btnCancel.ModalResult := mrCancel;

		btnOk.Width := 75;
		btnCancel.Width := 75;


		resultCode := frm.ShowModal();
		if(resultCode = mrYes) then begin
			nr := tryToParseInt(inputName.Text);

			if(nr > 0) then begin
				resourceData.I['count'] := nr;
				resourceBox.Items[resourceBox.ItemIndex] := IntToStr(nr) + ' x ' + nameBase;
			end else begin
				resourceBox.Items.Objects[resourceBox.ItemIndex].free();
				resourceBox.Items.Delete(resourceBox.ItemIndex);
			end;
			updateOkButtonAuto(resourceBox.parent);
		end;

		frm.free();
	end;

	procedure addResourceHandler(Sender: TObject);
	var
        frm: TForm;
		btnOk, btnCancel, btnClearFilter: TButton;
		selectResourceDropdown: TComboBox;
		inputAmount, filterInput: TEdit;
		resultCode, nr, resIndex: integer;
		resourceBox:TListBox;
	begin
		frm := CreateDialog('Add Resource', 300, 160);
		CreateLabel(frm, 10, 10, 'Select Resource to add');


        CreateLabel(frm, 10, 32, 'Filter');
        filterInput := CreateInput(frm, 50, 30, '');
        filterInput.width := 160;
        filterInput.name := 'filterInput';
        filterInput.text := '';
        filterInput.onchange := addResourceHandlerFilter;

        btnClearFilter := CreateButton(frm, 220, 28, 'Clear');
        btnClearFilter.width := 60;
        btnClearFilter.onclick := addResourceHandlerFilterClear;


		inputAmount := CreateInput(frm, 10, 58, '1');
		inputAmount.Width := 50;
		inputAmount.Name := 'inputAmount';
		inputAmount.Text := '1';
		inputAmount.onchange := addResourceHandlerValidator;

		selectResourceDropdown := CreateComboBox(frm, 64, 58, 210, nil);
		selectResourceDropdown.Style := csDropDownList;
		selectResourceDropdown.Name := 'selectResourceDropdown';
		selectResourceDropdown.ItemIndex := 0;
		selectResourceDropdown.onchange := addResourceHandlerValidator;
		//listRoomResources

		btnOk := CreateButton(frm, 50, 94, 'OK');
		btnOk.ModalResult := mrYes;
		btnOk.Name := 'btnOk';
		btnOk.Default := true;

		btnCancel := CreateButton(frm, 160, 94, 'Cancel');
		btnCancel.ModalResult := mrCancel;

		btnOk.Width := 75;
		btnCancel.Width := 75;

        addResourceHandlerFilter(filterInput);
        addResourceHandlerValidator(filterInput);

		resultCode := frm.ShowModal();
		if(resultCode = mrYes) then begin
			nr := tryToParseInt(inputAmount.Text);

			resourceBox := TListBox(sender.parent.FindComponent('resourceBox'));

            resIndex := getResourceIndex(selectResourceDropdown.Items[selectResourceDropdown.ItemIndex]);

			addResourceToListBox(resIndex, nr, resourceBox);
            // techResearchDialog2, roomUpgradeDialog2
			updateOkButtonAuto(resourceBox.parent);
		end;

		frm.free();
	end;

	procedure remRoomFuncHandler(Sender: TObject);
	var
		resourceBox: TListBox;
		index: integer;
	begin
		resourceBox := TListBox(sender.parent.FindComponent('roomFuncsBox'));

        deleteSelectedBoxItems(resourceBox);
	end;

    function stringContainsCI(haystack: String; needle: String): boolean;
    begin
        haystack := LowerCase(haystack);
        needle := LowerCase(needle);

        Result := (pos(needle, haystack) > 0);
    end;

    procedure genericDropdownFilter(targetDropdown: TComboBox; filterInput: TEdit; sourceList: TStringList);
	var
        filterText, prevSelectedValue: string;
        prevSelectedIndex, i: integer;
	begin

        prevSelectedIndex := targetDropdown.ItemIndex;
        prevSelectedValue := '';
        if(prevSelectedIndex >= 0) then begin
            prevSelectedValue := targetDropdown.Items[prevSelectedIndex];
        end;

        filterText := trim(filterInput.Text);
        targetDropdown.Items.clear();


        for i:=0 to sourceList.count - 1 do begin
            if(filterText = '') then begin
                targetDropdown.Items.addObject(sourceList[i], ObjectToElement(sourceList.Objects[i]));
            end else begin
                if(stringContainsCI(sourceList[i], filterText)) then begin
                    targetDropdown.Items.addObject(sourceList[i], ObjectToElement(sourceList.Objects[i]));
                end;
            end;
        end;

        targetDropdown.ItemIndex := 0;

        if(prevSelectedValue <> '') then begin
            setItemIndexByValue(targetDropdown, prevSelectedValue);
        end;
	end;

    procedure addResourceHandlerFilter(Sender: TObject);
	var
		selectResourceDropdown: TComboBox;
        filterInput: TEdit;
        filterText, prevSelectedValue: string;
        prevSelectedIndex, i: integer;
	begin
		selectResourceDropdown := TComboBox(sender.parent.FindComponent('selectResourceDropdown'));
		filterInput := TEdit(sender.parent.FindComponent('filterInput'));

        genericDropdownFilter(selectResourceDropdown, filterInput, listRoomResources);

        addResourceHandlerValidator(sender);
	end;

    procedure addResourceHandlerFilterClear(Sender: TObject);
	var
        filterInput: TEdit;
	begin
		filterInput := TEdit(sender.parent.FindComponent('filterInput'));
        if(filterInput.Text <> '') then begin
            filterInput.Text := '';
            addResourceHandlerFilter(Sender);
        end;
	end;

    procedure roomFuncHandlerFilter(Sender: TObject);
	var
		selectResourceDropdown: TComboBox;
        filterInput: TEdit;
        filterText, prevSelectedValue: string;
        prevSelectedIndex, i: integer;
	begin
		selectResourceDropdown := TComboBox(sender.parent.FindComponent('selectResourceDropdown'));
		filterInput := TEdit(sender.parent.FindComponent('filterInput'));

        genericDropdownFilter(selectResourceDropdown, filterInput, listRoomFuncs);

        roomFuncHandlerValidator(sender);
	end;

    procedure roomFuncHandlerFilterClear(Sender: TObject);
	var
        filterInput: TEdit;
	begin
		filterInput := TEdit(sender.parent.FindComponent('filterInput'));
        if(filterInput.Text <> '') then begin
            filterInput.Text := '';
            roomFuncHandlerFilter(Sender);
        end;
	end;

    procedure roomFuncHandlerValidator(Sender: TObject);
	var
		selectResourceDropdown: TComboBox;
        btnOk: TButton;
	begin
		selectResourceDropdown := TComboBox(sender.parent.FindComponent('selectResourceDropdown'));
		btnOk := TButton(sender.parent.FindComponent('btnOk'));

		btnOk.enabled := (selectResourceDropdown.ItemIndex >= 0);
	end;

    procedure addResourceHandlerValidator(Sender: TObject);
	var
		selectResourceDropdown: TComboBox;
        btnOk: TButton;
        inputAmount: TEdit;
        nr: integer;
	begin
        //inputAmount
		selectResourceDropdown := TComboBox(sender.parent.FindComponent('selectResourceDropdown'));
		inputAmount := TEdit(sender.parent.FindComponent('inputAmount'));

        nr := tryToParseInt(inputAmount.Text);


		btnOk := TButton(sender.parent.FindComponent('btnOk'));

		btnOk.enabled := ((selectResourceDropdown.ItemIndex >= 0) and (nr > 0));
	end;

	procedure addRoomFuncHandler(Sender: TObject);
	var
        frm: TForm;
		btnOk, btnCancel, btnClearFilter: TButton;
		selectResourceDropdown: TComboBox;
		resultCode, nr: integer;
		resourceBox:TListBox;
        filterInput: TEdit;
	begin
		frm := CreateDialog('Add Room Function', 300, 160);
		CreateLabel(frm, 10, 10, 'Select Room Function to add');


		CreateLabel(frm, 10, 32, 'Filter');
        filterInput := CreateInput(frm, 50, 30, '');
        filterInput.width := 160;
        filterInput.name := 'filterInput';
        filterInput.text := '';
        filterInput.onchange := roomFuncHandlerFilter;

        btnClearFilter := CreateButton(frm, 220, 28, 'Clear');
        btnClearFilter.width := 60;
        btnClearFilter.onclick := roomFuncHandlerFilterClear;


		selectResourceDropdown := CreateComboBox(frm, 10, 58, 270, nil);
		selectResourceDropdown.Style := csDropDownList;
		selectResourceDropdown.Name := 'selectResourceDropdown';
		selectResourceDropdown.ItemIndex := 0;
		selectResourceDropdown.onchange := roomFuncHandlerValidator;


		btnOk := CreateButton(frm, 50, 94, 'OK');
		btnOk.ModalResult := mrYes;
		btnOk.Name := 'btnOk';
		btnOk.Default := true;

		btnCancel := CreateButton(frm, 160, 94, 'Cancel');
		btnCancel.ModalResult := mrCancel;

		btnOk.Width := 75;
		btnCancel.Width := 75;

        roomFuncHandlerFilter(filterInput);
        roomFuncHandlerValidator(filterInput);

		resultCode := frm.ShowModal();
		if(resultCode = mrYes) then begin
			resourceBox := TListBox(sender.parent.FindComponent('roomFuncsBox'));

			// try to find existing
			if(resourceBox.Items.indexOf(selectResourceDropdown.Items[selectResourceDropdown.ItemIndex]) < 0) then begin
				resourceBox.Items.AddObject(selectResourceDropdown.Items[selectResourceDropdown.ItemIndex], selectResourceDropdown.Items.Objects[selectResourceDropdown.ItemIndex]);
			end;
			// addResourceToListBox(selectResourceDropdown.ItemIndex, nr, roomFuncsBox);
		end;

		frm.free();
	end;

	procedure layoutBrowseUpdateOk(Sender: TObject);
	var
		btnOk: TButton;
		inputName, inputPath: TEdit;
        oldFormLabel: TLabel;
		//selectUpgradeSlot: TComboBox;
	begin
		//selectUpgradeSlot
		//selectUpgradeSlot := TComboBox(sender.parent.FindComponent('selectUpgradeSlot'));
		inputPath := TEdit(sender.parent.FindComponent('inputPath'));
		inputName := TEdit(sender.parent.FindComponent('inputName'));
		btnOk := TButton(sender.parent.FindComponent('btnOk'));

		oldFormLabel := TLabel(sender.parent.FindComponent('oldFormLabel'));
        if(oldFormLabel <> nil) then begin
            btnOk.enabled := (trim(inputName.Text) <> '');
            exit;
        end;

		btnOk.enabled := (trim(inputPath.Text) <> '') and (trim(inputName.Text) <> '');
	end;

	procedure layoutBrowseHandler(Sender: TObject);
	var
		inputPath: TEdit;
		pathStr: string;
	begin
		inputPath := TEdit(sender.parent.FindComponent('inputPath'));
		pathStr := ShowOpenFileDialog('Select Spawns File', 'CSV Files|*.csv|All Files|*.*');
		if(pathStr <> '') then begin
			inputPath.Text := pathStr;
		end;
	end;

	function getLayoutDisplayName(layoutName: string; layoutPath: string; upgradeSlot: IInterface): string;
	begin
		//
		Result := layoutName + ' (' + GetRoomSlotName(upgradeSlot)+ '): ' + ExtractFileName(layoutPath);
	end;

	procedure addOrEditLayout(layoutsBox: TListBox; index: integer);
	var
        frm: TForm;
		btnOk, btnCancel, btnBrowse: TButton;
		inputName, inputPath: TEdit;
		title, layoutName, layoutPath, layoutDisplayName, selectedSlotStr: string;
		resultCode: integer;
		layoutData: TJsonObject;
		yOffset: integer;
		selectUpgradeSlot: TComboBox;
		roomSlotsOptional: TStringList;
		selectedSlot: IInterface;
        oldFormLabel: TLabel;
        existingLayer: IInterface;
	begin
		if(index < 0) then begin
			title := 'Add Room Layout';
		end else begin
			title := 'Edit Room Layout';
		end;
		frm := CreateDialog(title, 400, 190);

		yOffset := 0;

		CreateLabel(frm, 10, yOffset+10, 'Layout Name:');
		inputName := CreateInput(frm, 150, yOffset+8, '');
		inputName.Name := 'inputName';
		inputName.Text := '';
		inputName.onchange := layoutBrowseUpdateOk;
		inputName.Width := 150;

		// TODO: add a "custom" entry or such, which would generate a new KW from scratch
		//roomSlotsOptional := prependDummyEntry(currentListOfUpgradeSlots, '- DEFAULT -');
		// TODO: limit the list by which are filled already
		roomSlotsOptional := currentListOfUpgradeSlots;

		yOffset := yOffset + 24;
		CreateLabel(frm, 10, yOffset+10, 'Upgrade Slot:');
		selectUpgradeSlot := CreateComboBox(frm, 150, yOffset+8, 150, roomSlotsOptional);
		selectUpgradeSlot.Style := csDropDownList;
		selectUpgradeSlot.Name := 'selectUpgradeSlot';
		selectUpgradeSlot.ItemIndex := 0;

		yOffset := yOffset + 24;

        oldFormLabel := CreateLabel(frm, 10, yOffset+10, '');

		yOffset := yOffset + 32;
		CreateLabel(frm, 10, yOffset, 'Layout Spawns File:');
		inputPath := CreateInput(frm, 10, 20+yOffset, '');
		inputPath.Width := 320;
		inputPath.Name := 'inputPath';
		inputPath.Text := '';
		inputPath.onchange := layoutBrowseUpdateOk;

		btnBrowse := CreateButton(frm, 340, 18+yOffset, '...');
		btnBrowse.onclick := layoutBrowseHandler;

		yOffset := yOffset + 48;
		btnOk := CreateButton(frm, 100, yOffset, 'OK');
		btnOk.ModalResult := mrYes;
		btnOk.Name := 'btnOk';
		btnOk.Default := true;

		btnCancel := CreateButton(frm, 200, yOffset, 'Cancel');
		btnCancel.ModalResult := mrCancel;

		btnOk.Width := 75;
		btnCancel.Width := 75;

		if(index >= 0) then begin
			layoutData := layoutsBox.Items.Objects[index];
			inputName.Text  := layoutData.S['name'];
			inputPath.Text  := layoutData.S['path'];
			selectedSlotStr := layoutData.S['slot'];

            // special stuff: we might have layoutData.S['existing'] := FormToAbsStr(curLayout);
            if(layoutData.S['existing'] <> '') then begin
                existingLayer := WinningOverrideOrSelf(AbsStrToForm(layoutData.S['existing']));
                if(assigned(existingLayer)) then begin
                    oldFormLabel.Name := 'oldFormLabel';
                    oldFormLabel.Caption := 'Existing Layer: '+EditorID(existingLayer);
                end;
            end;

			selectedSlot := WinningOverrideOrSelf(AbsStrToForm(selectedSlotStr));
			setItemIndexByForm(selectUpgradeSlot, selectedSlot);
		end;

		layoutBrowseUpdateOk(btnOk);

		resultCode := frm.showModal();
		if(resultCode = mrYes) then begin
			layoutName := trim(inputName.Text);
			layoutPath := trim(inputPath.Text);


			selectedSlot := ObjectToElement(selectUpgradeSlot.Items.Objects[selectUpgradeSlot.ItemIndex]);



			layoutDisplayName := getLayoutDisplayName(layoutName, layoutPath, selectedSlot);

            selectedSlotStr := FormToAbsStr(selectedSlot);
			if(index < 0) then begin
				layoutData := TJsonObject.create();
				layoutData.S['name'] := layoutName;
				layoutData.S['path'] := layoutPath;
				layoutData.S['slot'] := selectedSlotStr;

				layoutsBox.Items.addObject(layoutDisplayName, layoutData);
			end else begin
				layoutData := layoutsBox.Items.Objects[index];


                // if we're updating and have an existing, mark it somehow
                if(assigned(existingLayer)) then begin
                    if(layoutPath = '') then begin
                        layoutDisplayName := getLayoutDisplayName(layoutName, EditorID(existingLayer), selectedSlot);
                    end;

                    if ((selectedSlotStr <> layoutData.S['slot']) or (layoutData.S['name'] <> layoutName) or (layoutData.S['path'] <> '')) then begin
                        layoutDisplayName := layoutDisplayName + ' *';
                    end;
                end;

				layoutData.S['name'] := layoutName;
				layoutData.S['path'] := layoutPath;
				layoutData.S['slot'] := selectedSlotStr;
				layoutsBox.Items[index] := layoutDisplayName;
			end;
			showRoomUpradeDialog2UpdateOk(layoutsBox.parent);
		end;

		frm.free();
		// roomSlotsOptional.free();
	end;

	procedure addLayoutHandler(Sender: TObject);
	var
		layoutsBox: TListBox;
	begin
		layoutsBox := TListBox(sender.parent.FindComponent('layoutsBox'));
		addOrEditLayout(layoutsBox, -1);
	end;

	procedure editLayoutHandler(Sender: TObject);
	var
		layoutsBox: TListBox;
	begin
		layoutsBox := TListBox(sender.parent.FindComponent('layoutsBox'));
		if(layoutsBox.ItemIndex < 0) then begin
			exit;
		end;
		addOrEditLayout(layoutsBox, layoutsBox.ItemIndex);
	end;

	procedure remLayoutHandler(Sender: TObject);
	var
		layoutsBox: TListBox;
	begin
		layoutsBox := TListBox(sender.parent.FindComponent('layoutsBox'));
		if(layoutsBox.ItemIndex < 0) then begin
			exit;
		end;

        deleteSelectedBoxItems(layoutsBox);
	end;

	function tryToParseFloat(s: string): float;
    var
        tmp, curChar, firstPart, secondPart, numberString: string;
        startOffset, i: integer;
		isNegative, hasPoint: boolean;
    begin    
        Result := 0.0;
        tmp := s;
        firstPart := '';
        secondPart := '';
		hasPoint:= false;

		isNegative := false;
		startOffset := 1;
		curChar := tmp[1];
		if(curChar = '-') then begin
			startOffset := 2;
			isNegative := true;
		end;

        for i:=startOffset to length(tmp) do begin
            curChar := tmp[i];
            if (curChar >= '0') and (curChar <= '9') then begin
				if(not hasPoint) then begin
					firstPart := firstPart + curChar;
				end else begin
					secondPart := secondPart + curChar;
				end;
            end else if(curChar = '.') then begin
				hasPoint := true;
			end;
        end;

		numberString := '';

		if(firstPart <> '') then begin
			numberString := firstPart;
		end else begin
			numberString := '0';
		end;

		if(secondPart <> '') then begin
			numberString := numberString + '.' +secondPart;
		end;

		if(isNegative) then begin
			numberString := '-'+numberString;
		end;

        if(numberString <> '') then begin
            Result := StrToFloat(numberString);
        end;
    end;

	procedure showRoomUpradeDialog2UpdateOk(Sender: TObject);
	var
		btnOk: TButton;
		inputName, inputDuration, inputPrefix: TEdit;
		selectUpgradeSlot, selectActionGroup, selectCobjKeyword: TComboBox;
		resourceBox, roomFuncsBox: TListBox;
		durationNr: float;
		layoutsGroup, resourceGroup: TGroupBox;
        parentWindow: TForm;
	begin
        parentWindow := findComponentParentWindow(sender);
		btnOk := TButton(parentWindow.FindComponent('btnOk'));

		inputName := TEdit(parentWindow.FindComponent('inputName'));
		inputPrefix := TEdit(parentWindow.FindComponent('inputPrefix'));
		inputDuration := TEdit(parentWindow.FindComponent('inputDuration'));

		selectUpgradeSlot := TComboBox(parentWindow.FindComponent('selectUpgradeSlot'));
		selectActionGroup := TComboBox(parentWindow.FindComponent('selectActionGroup'));
		selectCobjKeyword := TComboBox(parentWindow.FindComponent('selectCobjKeyword'));

		resourceBox := TListBox(parentWindow.FindComponent('resourceBox'));
		if(resourceBox = nil) then begin
			resourceGroup := TGroupBox (parentWindow.FindComponent('resourceGroup'));
			resourceBox := TListBox(resourceGroup.FindComponent('resourceBox'));
		end;

		durationNr := tryToParseFloat(trim(inputDuration.Text));

		btnOk.enabled := (trim(inputName.Text) <> '') and (trim(inputPrefix.Text) <> '') and (durationNr > 0) and (selectUpgradeSlot.ItemIndex >= 0) and (selectCobjKeyword.ItemIndex >= 0) and (selectActionGroup.ItemIndex >= 0) and (resourceBox.Items.count > 0);
	end;

    procedure showTechResearchDialog2UpdateOk(Sender: TObject);
	var
		btnOk: TButton;
		inputName, inputDuration, inputPrefix: TEdit;
		selectUpgradeSlot, selectActionGroup, selectCobjKeyword: TComboBox;
		resourceBox, roomFuncsBox: TListBox;
		durationNr: float;
		layoutsGroup, resourceGroup: TGroupBox;
        parentWindow: TForm;
	begin
        parentWindow := findComponentParentWindow(sender);
		btnOk := TButton(parentWindow.FindComponent('btnOk'));

		inputName := TEdit(parentWindow.FindComponent('inputName'));
		inputPrefix := TEdit(parentWindow.FindComponent('inputPrefix'));
		inputDuration := TEdit(parentWindow.FindComponent('inputDuration'));

		//selectUpgradeSlot := TComboBox(parentWindow.FindComponent('selectUpgradeSlot'));
		selectActionGroup := TComboBox(parentWindow.FindComponent('selectActionGroup'));
		selectCobjKeyword := TComboBox(parentWindow.FindComponent('selectCobjKeyword'));

		resourceBox := TListBox(parentWindow.FindComponent('resourceBox'));
		if(resourceBox = nil) then begin
			resourceGroup := TGroupBox (parentWindow.FindComponent('resourceGroup'));
			resourceBox := TListBox(resourceGroup.FindComponent('resourceBox'));
		end;

		durationNr := tryToParseFloat(trim(inputDuration.Text));

        //selectActionGroup.enabled
        if(selectActionGroup.enabled) then begin
            btnOk.enabled := (trim(inputName.Text) <> '') and (trim(inputPrefix.Text) <> '') and (durationNr > 0) and (selectCobjKeyword.ItemIndex >= 0) and (selectActionGroup.ItemIndex >= 0) and (resourceBox.Items.count > 0);
        end else begin
            btnOk.enabled := (trim(inputName.Text) <> '') and (trim(inputPrefix.Text) <> '') and (durationNr > 0) and (selectCobjKeyword.ItemIndex >= 0) and (resourceBox.Items.count > 0);
        end;
	end;

    procedure roomUpgradeTypeChanged(sender: TObject);
    const
        minusOne = -1;
    var
        selectCobjKeyword, selectActionGroup: TComboBox;
        parentWindow: TForm;
        prevSelection, defaultKw: IInterface;
        tmpIndex: integer;
        assignDepAtStart, assignDepAtEnd, defaultConstMarkers, disableClutter, disableGarbarge, realTimeTimer: TCheckBox;
	begin
        parentWindow := findComponentParentWindow(sender);
		selectActionGroup := TComboBox(parentWindow.FindComponent('selectActionGroup'));
		selectCobjKeyword := TComboBox(parentWindow.FindComponent('selectCobjKeyword'));

        assignDepAtStart    := TCheckBox(parentWindow.FindComponent('assignDepAtStart'));
        assignDepAtEnd      := TCheckBox(parentWindow.FindComponent('assignDepAtEnd'));
        defaultConstMarkers := TCheckBox(parentWindow.FindComponent('defaultConstMarkers'));
        disableClutter      := TCheckBox(parentWindow.FindComponent('disableClutter'));
        disableGarbarge     := TCheckBox(parentWindow.FindComponent('disableGarbarge'));
        realTimeTimer       := TCheckBox(parentWindow.FindComponent('realTimeTimer'));

        prevSelection := nil;
        defaultKw     := nil;

        if(selectCobjKeyword.ItemIndex >= 0) then begin
            prevSelection := ObjectToElement(selectCobjKeyword.Items.Objects[selectCobjKeyword.ItemIndex]);
        end;

        //  update selectCobjKeyword
        case(selectActionGroup.ItemIndex) of
            // fun fact: case...of can't do negative number literals
            minusOne:
                begin
                    selectCobjKeyword.enabled := false;
                end;
            0:
                begin
                    defaultKw := defaultConstructionKw;
                    selectCobjKeyword.enabled := true;
                    selectCobjKeyword.Items := listKeywordsConstruct;
                    // check some
                    assignDepAtStart.checked    := true;
                    assignDepAtEnd.checked      := false;
                    defaultConstMarkers.checked := true;
                    disableClutter.checked      := true;
                    disableGarbarge.checked     := true;
                    realTimeTimer.checked       := false;
                end;
            1:
                begin
                    defaultKw := defaultUpgradeKw;
                    selectCobjKeyword.enabled := true;
                    selectCobjKeyword.Items := listKeywordsUpgrade;
                    // uncheck all
                    assignDepAtStart.checked    := false;
                    assignDepAtEnd.checked      := false;
                    defaultConstMarkers.checked := false;
                    disableClutter.checked      := false;
                    disableGarbarge.checked     := false;
                    realTimeTimer.checked       := false;
                end;
        end;

        if(prevSelection <> nil) then begin
            tmpIndex := indexOfElement(selectCobjKeyword.Items, prevSelection);
            if(tmpIndex >= 0) then begin
                selectCobjKeyword.ItemIndex := tmpIndex;
                exit;
            end;
        end;

        setItemIndexByForm(selectCobjKeyword, defaultKw);
        showRoomUpradeDialog2UpdateOk(sender);
    end;

    procedure updateOkButtonAuto(obj: TObject);
    var
        frm: TForm;
    begin
        frm := findComponentParentWindow(obj);

        if(frm.Name = 'roomConfigDialog') then begin
            updateRoomConfigOkBtn(obj);
        end else if(frm.Name = 'roomUpgradeDialog1') then begin
            updateRoomUpgrade1OkBtn(obj);
        end else if(frm.Name = 'roomUpgradeDialog2') then begin
            showRoomUpradeDialog2UpdateOk(obj);
        end else if(frm.Name = 'techResearchDialog2') then begin
            showTechResearchDialog2UpdateOk(obj);
        end;
    end;

    function getModelArrayIndex(str: string; modelArray: TStringList): integer;
    var
        i: integer;
    begin
        for i:=0 to modelArray.count-1 do begin
            if(strEndsWithCI(str, modelArray[i])) then begin
                Result := i;
                exit;
            end;
        end;

        Result := 0;
    end;

    procedure fillCobjKeywordFromExisting(selectCobjKeyword: TComboBox; existingCobj: IInterface);
    var
        fnam, firstEntry, keyword: IInterface;
        index: integer;
    begin
        keyword := nil;
        existingCobj := WinningOverrideOrSelf(existingCobj);
        fnam := ElementByPath(existingCobj, 'FNAM');
        if(ElementCount(fnam) < 1) then begin
            exit;
        end;
        // take the first entry in here
        keyword := LinksTo(ElementByIndex(fnam, 0));

        if(not assigned(keyword)) then begin
            exit;
        end;

        setItemIndexByForm(selectCobjKeyword, keyword);
    end;

    procedure fillResourceItemsFromExisting(resourceBox: TListBox; script: IInterface);
    var
        curStruct, ResourceCost, curResObject: IInterface;
        i, resCount, resIndex: integer;
        jsonEntry: TJsonObject;
    begin
        // the not-so-hard part
            // resources
            // go into resourceBox.Items as JSON

        ResourceCost := getScriptProp(script, 'ResourceCost');
        if(not assigned(ResourceCost)) then begin
            //AddMessage
            exit;
        end;

        for i:=0 to ElementCount(ResourceCost)-1 do begin
            curStruct := ElementByIndex(ResourceCost, i);

            curResObject := WinningOverrideOrSelf(getStructMember(curStruct, 'Item'));
            resCount     := getStructMember(curStruct, 'iCount');

            // now find the index
            resIndex := indexOfElement(listRoomResources, curResObject);

            addResourceToListBox(resIndex, resCount, resourceBox);
        end;
    end;

    procedure fillRoomFunctionsFromExisting(roomFuncsBox: TListBox; script: IInterface);
    var
        i, roomFuncIndex: integer;
        ProvidedFunctionality, curRoomFunc, gotRoomFunc: IInterface;
        gotRoomFuncStr: string;
    begin
        ProvidedFunctionality := getScriptProp(script, 'ProvidedFunctionality');
        if(not assigned(ProvidedFunctionality)) then begin
            exit;
        end;

        for i:=0 to ElementCount(ProvidedFunctionality)-1 do begin
            curRoomFunc := getObjectFromProperty(ProvidedFunctionality, i);
            if(not assigned(curRoomFunc)) then begin
                AddMessage('WARNING: empty entry in list of room functions, skipping.');
                continue;
            end;
            curRoomFunc := WinningOverrideOrSelf(curRoomFunc);
            roomFuncIndex := indexOfElement(listRoomFuncs, curRoomFunc);
            if(roomFuncIndex < 0) then begin
                AddMessage('WARNING: failed to find '+EditorID(curRoomFunc)+' in list of room functions, adding.');
                gotRoomFuncStr := GetElementEditValues(curRoomFunc, 'FULL');
                addObjectDupIgnore(listRoomFuncs, gotRoomFuncStr, curRoomFunc);
            end else begin
                gotRoomFuncStr := listRoomFuncs[roomFuncIndex];
            end;

            roomFuncsBox.Items.AddObject(gotRoomFuncStr, curRoomFunc);
        end;
    end;

    function getDesignerObjectsFromUpgradeScript(script: IInterface): TJsonObject;
    var
        cobjDesc : string;
        RoomLayouts, firstLayout, layoutScript, nameHolder, descHolder, curNameHolder, curDescHolder: IInterface;
        i: integer;
    begin
        Result := nil;
        RoomLayouts := getScriptProp(script, 'RoomLayouts');

        for i:=0 to ElementCount(RoomLayouts)-1 do begin
            firstLayout := WinningOverrideOrSelf(getObjectFromProperty(RoomLayouts, i));

            layoutScript := getScript(firstLayout, 'SimSettlementsV2:HQ:Library:Weapons:HQRoomLayout');
            curNameHolder := getScriptProp(layoutScript, 'DesignerNameHolder');
            curDescHolder := getScriptProp(layoutScript, 'InformationMessage');

            if(assigned(curNameHolder)) then begin
                nameHolder := curNameHolder;
            end;

            if(assigned(curDescHolder)) then begin
                descHolder := curDescHolder;
            end;

            if(assigned(descHolder) and assigned(nameHolder)) then begin
                break;
            end;
        end;

        if ((not assigned(descHolder)) and (not assigned(nameHolder))) then begin
            exit;
        end;

        nameHolder := WinningOverrideOrSelf(nameHolder);
        descHolder := WinningOverrideOrSelf(descHolder);

        Result := TJsonObject.create;
        Result.S['name'] := FormToAbsStr(getExistingElementOverrideOrClosest(nameHolder, targetFile));
        Result.S['desc'] := FormToAbsStr(getExistingElementOverrideOrClosest(descHolder, targetFile));
    end;


    procedure fillDescriptionDataFromExisting(existingCobj, existingMiscScript: IInterface);
    var
        cobjDesc : string;
        RoomLayouts, firstLayout, layoutScript, nameHolder, descHolder: IInterface;
        designerData: TJsonObject;
    begin
        existingCobj := WinningOverrideOrSelf(existingCobj);
        // first, get the COBJ's description
        currentUpgradeDescriptionData.S['mechanicsDesc'] := getElementEditValues(existingCobj, 'DESC');

        designerData := getDesignerObjectsFromUpgradeScript(existingMiscScript);

        if(assigned(designerData)) then begin
            nameHolder := WinningOverrideOrSelf(AbsStrToForm(designerData.S['name']));
            descHolder := WinningOverrideOrSelf(AbsStrToForm(designerData.S['desc']));

            if(assigned(nameHolder)) then begin
                currentUpgradeDescriptionData.S['designerName'] := getElementEditValues(nameHolder, 'FULL');
            end;

            if(assigned(descHolder)) then begin
                currentUpgradeDescriptionData.S['designDesc'] := getElementEditValues(descHolder, 'DESC');
            end;

            designerData.free();
        end;

    end;

    procedure fillLayoutsFromExisting(layoutsBox: TListBox; script: IInterface);
    var
        i: integer;
        RoomLayouts, curLayout, selectedSlot: IInterface;
        layoutData: TJsonObject;
        layoutDisplayName, layoutName, layoutPath: string;
    begin
        RoomLayouts := getScriptProp(script, 'RoomLayouts');
        for i:=0 to ElementCount(RoomLayouts)-1 do begin
            curLayout := WinningOverrideOrSelf(getObjectFromProperty(RoomLayouts, i));

            layoutName := GetElementEditValues(curLayout, 'FULL');

            selectedSlot := WinningOverrideOrSelf(findSlotMiscFromLayout(curLayout));

            layoutData := TJsonObject.create();
            // I need name and slot
            layoutData.S['name'] := layoutName;
            layoutData.S['slot'] := FormToAbsStr(selectedSlot);
            // resourceJson.S['path']
            layoutData.S['existing'] := FormToAbsStr(curLayout);

            layoutPath := EditorID(curLayout);

            layoutDisplayName := getLayoutDisplayName(layoutName, layoutPath, selectedSlot);

            layoutsBox.Items.addObject(layoutDisplayName, layoutData);
        end;
    end;

    procedure fillObjectTypeActionGroups(hq: IInterface; dropdownBox: TComboBox);
    var
        hqManager, hqManagerScript: IInterface;
        constructionGroup, upgradeGroup: IInterface;
    begin
        hqManager := getManagerForHq(hq);
        hqManagerScript := getHqManagerScript(hqManager);
        constructionGroup := getScriptProp(hqManagerScript, 'RoomConstructionActionGroup');
        upgradeGroup := getScriptProp(hqManagerScript, 'RoomUpgradesActionGroup');

        constructionGroup := WinningOverrideOrSelf(constructionGroup);
        upgradeGroup := WinningOverrideOrSelf(upgradeGroup);

        // 0 = construction
        // 1 = upgrade
        dropdownBox.Items.AddObject('Construction', constructionGroup);
        dropdownBox.Items.AddObject('Upgrade', upgradeGroup);
    end;

    procedure fillSlotsFromExisting(itemList: TStringList; miscScript: IInterface);
    var
        AdditionalUpgradeSlots, curSlot: IInterface;
        i: integer;
    begin
        AdditionalUpgradeSlots := getScriptProp(miscScript, 'AdditionalUpgradeSlots');

        for i:=0 to ElementCount(AdditionalUpgradeSlots)-1 do begin
            curSlot := WinningOverrideOrSelf(getObjectFromProperty(AdditionalUpgradeSlots, i));
            itemList.addObject(getElementEditValues(curSlot, 'FULL'), curSlot);
        end;
    end;

    procedure menuCopyAllHandler(sender: TObject);
    var
        item: TMenuItem;
        resourceBox: TListBox;
        maybeMenu: TPopupMenu;
        jsonStr: string;
    begin
        // sender should be the item here
        // item := TMenuItem(sender);
        maybeMenu := currentOpenMenu; // because item.getParentMenu() isn't implemented in xedit
        resourceBox := TListBox(maybeMenu.PopupComponent);

        jsonStr := '';
        // serialize the items to JSON
        if(resourceBox.Name = 'resourceBox') then begin
            jsonStr := serializeResourceListToJson(resourceBox.Items);
        end else if(resourceBox.Name = 'roomFuncsBox') then begin
            jsonStr := serializeRoomFuncListToJson(resourceBox.Items);
        end else if(resourceBox.Name = 'layoutsBox') then begin
            jsonStr := serializeLayoutListToJson(resourceBox.Items);
        end else if(resourceBox.Name = 'listSlots') then begin
            jsonStr := serializeSlotListToJson(resourceBox.Items);
        end;
        setFakeClipboardText(jsonStr);
    end;

    procedure remResourceHandler(Sender: TObject);
	var
		resourceBox: TListBox;
	begin
		resourceBox := TListBox(sender.parent.FindComponent('resourceBox'));
		deleteSelectedBoxItems(resourceBox);
	end;

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

    procedure deleteSelectedBoxItems(box: TListBox);
    var
		index, i: integer;
        needsFree, isRoomConfig: boolean;
        parentForm: TForm;
    begin
        if(box.SelCount <= 0) then begin
			exit;
		end;
        needsFree := false;

        if ((box.Name = 'resourceBox') or (box.Name = 'layoutsBox')) then begin
            needsFree := true;
        end;

        for i:=box.Items.count-1 downto 0 do begin
            if (box.Selected(i)) then begin
                if ((box.Items.Objects[i] <> nil) and needsFree) then begin
                    box.Items.Objects[i].free();
                end;
                box.Items.Delete(i);
            end;
        end;

        updateOkButtonAuto(box);
    end;

    procedure copySelectedBoxItems(box: TListBox);
    var
        jsonStr: string;
        tempList: TStringList;
        i: integer;
    begin
        tempList := TStringList.create;
        jsonStr := '';
        if(box.Name = 'resourceBox') then begin
            // copy over
            for i:=0 to box.Items.count-1 do begin
                if(box.Selected(i)) then begin
                    tempList.AddObject(box.Items[i], box.Items.Objects[i]);
                end;
            end;

            // serialize the items to JSON
            jsonStr := serializeResourceListToJson(tempList);
        end else if(box.Name = 'roomFuncsBox') then begin
            for i:=0 to box.Items.count-1 do begin
                if(box.Selected(i)) then begin
                    tempList.AddObject(box.Items[i], ObjectToElement(box.Items.Objects[i]));
                end;
            end;
            jsonStr := serializeRoomFuncListToJson(tempList);
        end else if(box.Name = 'layoutsBox') then begin
            for i:=0 to box.Items.count-1 do begin
                if(box.Selected(i)) then begin
                    tempList.AddObject(box.Items[i], box.Items.Objects[i]);
                end;
            end;

            jsonStr := serializeLayoutListToJson(tempList);
        end else if(box.Name = 'listSlots') then begin
            for i:=0 to box.Items.count-1 do begin
                if(box.Selected(i)) then begin
                    if(box.Items.Objects[i] <> nil) then begin
                        tempList.AddObject(box.Items[i], ObjectToElement(box.Items.Objects[i]));
                    end else begin
                        tempList.Add(box.Items[i]);
                    end;
                end;
            end;

            jsonStr := serializeSlotListToJson(tempList);
        end;
        setFakeClipboardText(jsonStr);

        tempList.free();
    end;

    procedure pasteBoxItems(box: TListBox);
    var
        jsonStr: string;
    begin
        jsonStr := getFakeClipboardText();
        if(jsonStr <> '') then begin
            if(box.Name = 'resourceBox') then begin
                deserializeResourceJsonIntoList(jsonStr, box.Items);
            end else if(box.Name = 'roomFuncsBox') then begin
                deserializeRoomFuncsJsonIntoList(jsonStr, box.Items);
            end else if(box.Name = 'layoutsBox') then begin
                // serializeLayoutListToJson deserializeLayoutJsonIntoList
                deserializeLayoutJsonIntoList(jsonStr, box.Items);
            end else if(box.Name = 'listSlots') then begin
                deserializeSlotJsonIntoList(jsonStr, box.Items);
            end;
        end;

        updateOkButtonAuto(box);
    end;

    function generateUpgradeDescription(completionTime: float; entries: TStringList): string;
    var
        descriptionText: string;
        numDays: float;
    begin
        if(entries.count > 0) then begin
            descriptionText := joinLines(entries, ' | ') +' | Completion Time: ';
        end else begin
            descriptionText := 'Completion Time: ';
        end;

		numDays := round(completionTime / 24 * 10) / 10;
		if(floatEquals(numDays, 1)) then begin
			descriptionText := descriptionText + '1 Day';
		end else begin
			descriptionText := descriptionText + FloatToStr(numDays) + ' Days';
		end;

        Result := descriptionText;
    end;

    procedure regenerateMechancisDescription(sender: TObject);
    var
        dialogParent: TForm;
        inputMechanics: TCustomMemo; //CreateMultilineInput
        resourceBox: TListBox;
        inputDuration: TEdit;
        roomFuncsGroup :TGroupBox;
        duration: float;
    begin
        dialogParent := findComponentParentWindow(sender);
        inputMechanics := TCustomMemo(dialogParent.findComponent('inputMechanics'));

        resourceBox := TListBox(currentUpgradeDialog.FindComponent('roomFuncsBox'));
        inputDuration := TEdit(currentUpgradeDialog.FindComponent('inputDuration'));

        if(resourceBox = nil) then begin
            roomFuncsGroup := TGroupBox(currentUpgradeDialog.FindComponent('roomFuncsGroup'));
            if(nil <> roomFuncsGroup) then begin
                resourceBox := TListBox(roomFuncsGroup.FindComponent('roomFuncsBox'));
            end;
        end;

        duration := tryToParseFloat(inputDuration.Text);
        inputMechanics.Text := generateUpgradeDescription(duration, resourceBox.Items);
    end;

    procedure showDescriptionEditDialog(sender: TObject);
    var
        frm, dialogParent: TForm;
		btnOk, btnCancel: TButton;
        resultCode, yOffset, i: integer;
        inputDesigner: TEdit;
        inputMechanics, inputDesign: TCustomMemo; //CreateMultilineInput

		resourceBox: TListBox;
        roomFuncsGroup :TGroupBox;

        duration: float;
        inputDuration: TEdit;

        regenMechanicsbtn: TButton;
    begin
        dialogParent := findComponentParentWindow(sender);
        currentUpgradeDialog := dialogParent;


        yOffset := 10;
        frm := CreateDialog('Room Upgrade Details', 410, 360);
        CreateLabel(frm, yOffset, 10, 'Designer Name:');
        inputDesigner := CreateInput(frm, yOffset, 26, escapeString(currentUpgradeDescriptionData.S['designerName']));
        inputDesigner.width := 200;

        yOffset := yOffset + 50;

        CreateLabel(frm, 10, yOffset+7, 'Mechanics description:');
        inputMechanics := CreateMultilineInput(frm, 10, yOffset+32, 380, 80, escapeString(currentUpgradeDescriptionData.S['mechanicsDesc']));
        inputMechanics.Name := 'inputMechanics';
        regenMechanicsbtn := CreateButton(frm, 130, yOffset, 'Regenerate');
        regenMechanicsbtn.onclick := regenerateMechancisDescription;


        yOffset := yOffset + 120;
        CreateLabel(frm, 10, yOffset, 'Design description:');
        inputDesign := CreateMultilineInput(frm, 10, yOffset+16, 380, 80, escapeString(currentUpgradeDescriptionData.S['designDesc']));

        yOffset := yOffset + 120;

        btnOk := CreateButton(frm, 120, yOffset, 'OK');
		btnOk.ModalResult := mrYes;
		btnOk.Name := 'btnOk';
		btnOk.Default := true;

		btnCancel := CreateButton(frm, 220, yOffset, 'Cancel');
		btnCancel.ModalResult := mrCancel;

		btnOk.Width := 75;
		btnCancel.Width := 75;

        // try to auto-fill mechanics
		resourceBox := TListBox(dialogParent.FindComponent('roomFuncsBox'));
        inputDuration := TEdit(dialogParent.FindComponent('inputDuration'));

        duration := tryToParseFloat(inputDuration.Text);

        if(resourceBox = nil) then begin
            roomFuncsGroup := TGroupBox(dialogParent.FindComponent('roomFuncsGroup'));
            if(nil <> roomFuncsGroup) then begin
                resourceBox := TListBox(roomFuncsGroup.FindComponent('roomFuncsBox'));
            end;
        end;
        if(resourceBox <> nil) then begin
            if(inputMechanics.Text = '') then begin
                // autofill here
                inputMechanics.Text := generateUpgradeDescription(duration, resourceBox.Items);
            end;
        end;

        resultCode := frm.ShowModal();
		if(resultCode = mrYes) then begin
            currentUpgradeDescriptionData.S['designerName']     := trim(inputDesigner.Text);
            currentUpgradeDescriptionData.S['mechanicsDesc']    := trim(inputMechanics.Text);
            currentUpgradeDescriptionData.S['designDesc']       := trim(inputDesign.Text);
        end;
    end;

    procedure menuCopySelectHandler(sender: TObject);
    var
        resourceBox: TListBox;
        maybeMenu: TPopupMenu;
    begin
        // sender should be the item here
        // item := TMenuItem(sender);
        maybeMenu := currentOpenMenu; // because item.getParentMenu() isn't implemented in xedit
        resourceBox := TListBox(maybeMenu.PopupComponent);

        copySelectedBoxItems(resourceBox);
    end;

    procedure menuDeleteHandler(sender: TObject);
    var
        item: TMenuItem;
        resourceBox: TListBox;
        maybeMenu: TPopupMenu;
        jsonStr: string;
    begin
        // sender should be the item here
        // item := TMenuItem(sender);
        maybeMenu := currentOpenMenu; // because item.getParentMenu() isn't implemented in xedit
        resourceBox := TListBox(maybeMenu.PopupComponent);

        deleteSelectedBoxItems(resourceBox);
    end;

    procedure menuPasteHandler(sender: TObject);
    var
        item: TMenuItem;
        resourceBox: TListBox;
        maybeMenu: TPopupMenu;
        jsonStr: string;
    begin
        // sender should be the item here
        // item := TMenuItem(sender);
        maybeMenu := currentOpenMenu; // because item.getParentMenu() isn't implemented in xedit
        resourceBox := TListBox(maybeMenu.PopupComponent);

        pasteBoxItems(resourceBox);
    end;

    procedure menuOpenHandler(sender: TObject);
    var
        resourceBox: TListBox;
        maybeMenu: TPopupMenu;
        copySelectedItem, deleteItem, pasteItem, copyAllItem: TMenuItem;
    begin
        maybeMenu := TPopupMenu(sender);

        currentOpenMenu := maybeMenu;

        resourceBox := TListBox(maybeMenu.PopupComponent);

        copySelectedItem := maybeMenu.FindComponent('copySelectedItem');
        copyAllItem := maybeMenu.FindComponent('copyAllItem');
        deleteItem       := maybeMenu.FindComponent('deleteItem');
        pasteItem        := maybeMenu.FindComponent('pasteItem');

        if(resourceBox.Items.count = 0) then begin
            copyAllItem.enabled := false;
        end else begin
            copyAllItem.enabled := true;
        end;

        if(resourceBox.SelCount <= 0) then begin
            copySelectedItem.enabled := false;
            deleteItem.enabled := false;
        end else begin
            copySelectedItem.enabled := true;
            deleteItem.enabled := true;
        end;

        // which box do we have?
        if(resourceBox.Name = 'resourceBox') then begin
            pasteItem.enabled := hasClipboardData('resources');
        end else if(resourceBox.Name = 'roomFuncsBox') then begin
            pasteItem.enabled := hasClipboardData('roomfuncs');
        end else if(resourceBox.Name = 'layoutsBox') then begin
            pasteItem.enabled := hasClipboardData('layouts');
        end else if(resourceBox.Name = 'listSlots') then begin
            pasteItem.enabled := hasClipboardData('slots');
        end;
    end;

    procedure setupMenu(list: TListBox);
    var
        copySelectedItem, copyAllItem, pasteItem, deleteItem: TMenuItem;
        menu: TPopupMenu;
    begin
        menu  := TPopupMenu.Create(list);
        //menu.Name := 'wtf';
        list.PopupMenu  := menu;
        menu.onPopup := menuOpenHandler;

        copySelectedItem := TMenuItem.create(list.PopupMenu);
        copySelectedItem.Name := 'copySelectedItem';
        copySelectedItem.caption := 'Copy Selected';
        copySelectedItem.onclick := menuCopySelectHandler;

        copyAllItem := TMenuItem.create(list.PopupMenu);
        copyAllItem.Name := 'copyAllItem';
        copyAllItem.caption := 'Copy All';
        copyAllItem.onclick := menuCopyAllHandler;

        pasteItem := TMenuItem.create(list.PopupMenu);
        pasteItem.Name := 'pasteItem';
        pasteItem.caption := 'Paste';
        pasteItem.onclick := menuPasteHandler;

        deleteItem := TMenuItem.create(list.PopupMenu);
        deleteItem.Name := 'deleteItem';
        deleteItem.caption := 'Delete';
        deleteItem.onclick := menuDeleteHandler;

        menu.Items.add(copySelectedItem);
        menu.Items.add(copyAllItem);
        menu.Items.add(pasteItem);
        menu.Items.add(deleteItem);
    end;

    procedure listboxKeyPressHandler(Sender: TObject; var Key: Word; Shift: TShiftState);
    var
        box: TListBox;
        i: integer;
    begin//procedure FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
        box := TListBox(sender);

        case (key) of
            65: begin // a key
                    if(Shift = [ssCtrl]) then begin
                        // ctrl + a
                        // box.selectAll(); // not implemented
                        for i:=0 to box.Items.count-1 do begin
                            box.selected(i) := true; // yes, really
                        end;
                    end;
                end;
            67: begin   // c key
                    if(Shift = [ssCtrl]) then begin
                        copySelectedBoxItems(box);
                    end;
                end;
            68: begin   // d key
                if(Shift = [ssCtrl]) then begin
                        // ctrl + d = deselect
                        // box.selectAll(); // not implemented
                        for i:=0 to box.Items.count-1 do begin
                            box.selected(i) := false; // deselect
                        end;
                    end;
                end;
            86: begin   // v key
                    if(Shift = [ssCtrl]) then begin
                        pasteBoxItems(box);
                    end;
                end;
            88: begin   // x key
                    if(Shift = [ssCtrl]) then begin
                        copySelectedBoxItems(box);
                        deleteSelectedBoxItems(box);
                    end;
                end;
            VK_DELETE:
                begin
                    deleteSelectedBoxItems(box);
                end;
        end;
    end;

	procedure showRoomUpgradeDialog2(targetRoomConfig, existingElem: IInterface);
	var
        frm: TForm;
		btnOk, btnCancel: TButton;
		resultCode, curY, secondRowOffset, thirdRowOffset: integer;

		selectUpgradeSlot, selectDepartment, selectModel, selectMiscModel, selectActionGroup, selectCobjKeyword: TComboBox;
		assignDepAtEnd, assignDepAtStart, disableClutter, disableGarbarge, defaultConstMarkers, realTimeTimer: TCheckBox;
		doRegisterCb: TCheckBox;
		departmentList, modelList, modelListMisc: TStringList;
		inputName, inputPrefix, inputDuration: TEdit; ///Duration: Float - default to 24

		resourceGroup: TGroupBox;
		resourceBox: TListBox;
		resourceAddBtn, resourceRemBtn, resourceEdtBtn, descriptionButton: TButton;

		roomFuncsGroup: TGroupBox;
		roomFuncsBox: TListBox;
		roomFuncAddBtn, roomFuncRemBtn: TButton;

        extraSlotsGroup: TGroupBox;
		extraSlotsBox: TListBox;
		extraSlotsAddBtn, extraSlotsRemBtn: TButton;

		layoutsGroup: TGroupBox;
		layoutsBox: TListBox;
		layoutsAddBtn, layoutsRemBtn, layoutsEdtBtn: TButton;

		modelStr, modelStrMisc, upgradeName, windowCaption, shapeKeywordBase, MiscModelFilename, artObjEdid, mechanicsDescr: string;
		targetDepartment: IInterface;

		roomUpgradeMisc, roomUpgradeActi: IInterface;
		upgradeDuration: float;

		roomShapeKeyword, upgradeSlot, actionGroup, cobjSfx: IInterface;

        // existing stuff
        existingMiscScript, existingActi, existingActiScript, existingCobj, cobjKeyword: IInterface;

        modelIndex: integer;

        actiData : TJsonObject;
	begin
		// load the slots for what we have
        currentListOfUpgradeSlots := getRoomUpgradeSlots(WinningOverrideOrSelf(targetHQ), WinningOverrideOrSelf(targetRoomConfig));

		secondRowOffset := 300;
        actiData := nil;
        windowCaption := 'Generating Room Upgrade';
        if(assigned(existingElem)) then begin
            existingElem := WinningOverrideOrSelf(existingElem);
            windowCaption := 'Updating Room Upgrade';

            existingMiscScript := getScript(existingElem, 'SimSettlementsV2:HQ:BaseActionTypes:HQRoomUpgrade');

            actiData := findRoomUpgradeActivatorsAndCobjs(existingElem);

            existingActi := nil;
            existingCobj := nil;

            // try to find the acti model
            if (actiData.O['1'].S['acti'] <> '') then begin
                existingActi := WinningOverrideOrSelf(AbsStrToForm(actiData.O['1'].S['acti']));
            end else begin
                if (actiData.O['2'].S['acti'] <> '') then begin
                    existingActi := WinningOverrideOrSelf(AbsStrToForm(actiData.O['2'].S['acti']));
                end else begin
                    if (actiData.O['3'].S['acti'] <> '') then begin
                        existingActi := WinningOverrideOrSelf(AbsStrToForm(actiData.O['3'].S['acti']));
                    end;
                end;
            end;

            if (actiData.O['1'].S['cobj'] <> '') then begin
                existingCobj := WinningOverrideOrSelf(AbsStrToForm(actiData.O['1'].S['cobj']));
            end else begin
                if (actiData.O['2'].S['cobj'] <> '') then begin
                    existingCobj := WinningOverrideOrSelf(AbsStrToForm(actiData.O['2'].S['cobj']));
                end else begin
                    if (actiData.O['3'].S['cobj'] <> '') then begin
                        existingCobj := WinningOverrideOrSelf(AbsStrToForm(actiData.O['3'].S['cobj']));
                    end;
                end;
            end;

            {
            // what was this even supposed to do?
            if(assigned(existingActi)) then begin
                // try to find the acti, too
                existingActi := findRoomUpgradeActivator(existingElem);
            end;
            }

        end;

        roomShapeKeyword := getRoomShapeKeywordFromConfig(targetRoomConfig);
        shapeKeywordBase := getRoomShapeUniquePart(EditorID(roomShapeKeyword));

        MiscModelFilename := shapeKeywordBase+'.nif';
        ArtObjEdid := 'SS2C2_AO_RoomShape_'+shapeKeywordBase;

		frm := CreateDialog(windowCaption, 620, 600);// x=+30 y=+20
		frm.Name := 'roomUpgradeDialog2';
		curY := 0;
		//if(not assigned(existingElem)) then begin
        CreateLabel(frm, 10, 10+curY, 'HQ: '+EditorID(targetHQ)+'.');
        CreateLabel(frm, 10, 28+curY, 'Room Config: '+EditorID(targetRoomConfig));
		//end;

		curY := curY + 46;

		CreateLabel(frm, 10, 10+curY, 'Name:*');
		inputName := CreateInput(frm, 100, 8+curY, '');
		inputName.Name := 'inputName';
		inputName.Text := '';
		inputName.width := 200;
		inputName.onChange := showRoomUpradeDialog2UpdateOk;

		CreateLabel(frm, secondRowOffset+10, 10+curY, 'EditorID Prefix:*');
		inputPrefix := CreateInput(frm, secondRowOffset+100, 8+curY, '');
		inputPrefix.Name := 'inputPrefix';
		inputPrefix.Text := '';
		inputPrefix.width := 200;
		inputPrefix.onChange := showRoomUpradeDialog2UpdateOk;


		curY := curY + 24;

		modelListMisc := prependNoneEntry(listModelsMisc);
		modelList := prependNoneEntry(listModels);
		//selectActionGroup
        // this is different now
		CreateLabel(frm, 10, 10+curY, 'Object Type:*');

		selectActionGroup := CreateComboBox(frm, 100, 8+curY, 500, nil);
		selectActionGroup.Style := csDropDownList;
		selectActionGroup.Name := 'selectActionGroup';
		selectActionGroup.ItemIndex := -1;
        fillObjectTypeActionGroups(targetHQ, selectActionGroup);
		selectActionGroup.onChange := roomUpgradeTypeChanged;



		curY := curY + 24;
		CreateLabel(frm, 10, 10+curY, 'Misc Model:');
		selectMiscModel := CreateComboBox(frm, 100, 8+curY, 500, modelListMisc);
		selectMiscModel.Style := csDropDownList;
		selectMiscModel.Name := 'selectMiscModel';
		selectMiscModel.ItemIndex := 0;

		curY := curY + 24;
		CreateLabel(frm, 10, 10+curY, 'Activator Model:');
		selectModel := CreateComboBox(frm, 100, 8+curY, 500, modelList);
		selectModel.Style := csDropDownList;
		selectModel.Name := 'selectModel';
		selectModel.ItemIndex := 0;

        //Stand_Hammer_Vertical.nif
        modelIndex := modelList.indexOf('Stand_Hammer_Vertical.nif');
        if(modelIndex > -1) then begin
            selectModel.ItemIndex := modelIndex;
        end;

        modelIndex := modelListMisc.indexOf(MiscModelFilename);
        if(modelIndex > -1) then begin
            selectMiscModel.ItemIndex := modelIndex;
        end;

		curY := curY + 24;
		CreateLabel(frm, 10, 10+curY, 'Upgrade slot:*');
		selectUpgradeSlot := CreateComboBox(frm, 100, 8+curY, 200, currentListOfUpgradeSlots);
		selectUpgradeSlot.Style := csDropDownList;
		selectUpgradeSlot.Name := 'selectUpgradeSlot';
		selectUpgradeSlot.onChange := showRoomUpradeDialog2UpdateOk;


        // add the decoration KW
        addObjectDupIgnore(listKeywordsConstruct, 'Decoration', SS2_WorkshopMenu_HQ_Administration_Decorate);
        // put the new dropdown here
        CreateLabel(frm, secondRowOffset+10, 10+curY, 'Submenu:*');
        //listKeywordsConstruct
        selectCobjKeyword := CreateComboBox(frm, secondRowOffset+100, 8+curY, 200, listKeywordsConstruct);
		selectCobjKeyword.Style := csDropDownList;
		selectCobjKeyword.Name := 'selectCobjKeyword';
		selectCobjKeyword.onChange := showRoomUpradeDialog2UpdateOk;


        secondRowOffset := 210;
        thirdRowOffset := 400;

		// selectUpgradeSlot.onChange := updateRoomUpgrade1OkBtn;
        // The 6 checkboxes
		curY := curY + 42;
		assignDepAtStart := CreateCheckbox(frm, 10, curY, 'Assign department to room at start');
        assignDepAtStart.Checked := true;
        assignDepAtStart.Name := 'assignDepAtStart';

		assignDepAtEnd := CreateCheckbox(frm, 10, curY + 16, 'Assign department to room at end');
        assignDepAtEnd.Name := 'assignDepAtEnd';

		defaultConstMarkers := CreateCheckbox(frm, secondRowOffset+10, curY, 'Use default construction markers');
		defaultConstMarkers.Checked := true;
        defaultConstMarkers.Name := 'defaultConstMarkers';

		disableClutter := CreateCheckbox(frm, secondRowOffset+10, curY + 16, 'Disable clutter on completion');
		disableClutter.Checked := true;
		disableClutter.Name := 'disableClutter';

		disableGarbarge:= CreateCheckbox(frm, thirdRowOffset+10, curY, 'Disable garbage on completion');
		disableGarbarge.Checked := true;
		disableGarbarge.Name := 'disableGarbarge';

		realTimeTimer:= CreateCheckbox(frm, thirdRowOffset+10, curY + 16, 'Real-Time Timer');
		realTimeTimer.Checked := false;
		realTimeTimer.Name := 'realTimeTimer';

		curY := curY + 50;

        extraSlotsGroup := CreateGroup(frm, 10, curY, 290, 64, 'Extra Slots');
        extraSlotsGroup.Name := 'slotsGroup';

        extraSlotsBox   := CreateListBox(extraSlotsGroup, 8, 16, 200, 48, nil);
		extraSlotsBox.Name := 'listSlots';
		extraSlotsBox.Multiselect := true;
        setupMenu(extraSlotsBox);
        extraSlotsBox.OnKeyDown := listboxKeyPressHandler;

		extraSlotsAddBtn := CreateButton(extraSlotsGroup, 210, 16, 'Add');
        extraSlotsRemBtn := CreateButton(extraSlotsGroup, 210, 40, 'Remove');

		extraSlotsAddBtn.Width := 60;
        extraSlotsRemBtn.Width := 60;

		extraSlotsAddBtn.onclick := addUpgradeSlotHandler;
        extraSlotsRemBtn.onclick := remUpgradeSlotHandler;


        secondRowOffset := 300;

		CreateLabel(frm, secondRowOffset+10, curY, 'Duration (hours):*');
		inputDuration := CreateInput(frm, secondRowOffset+150, curY-2, '24.0');
		inputDuration.width := 120;
		inputDuration.Name := 'inputDuration';
		inputDuration.Text := '24.0';
		inputDuration.onChange := showRoomUpradeDialog2UpdateOk;

		curY := curY + 24;
		CreateLabel(frm, secondRowOffset+10, curY+4, 'Give control to department:');
		departmentList := prependNoneEntry(listDepartmentObjects);

		selectDepartment := CreateComboBox(frm, secondRowOffset+150, curY, 200, departmentList);
		selectDepartment.Style := csDropDownList;
		selectDepartment.Name := 'selectDepartment';
		selectDepartment.ItemIndex := 0;
		selectDepartment.width := 120;
		//selectMainDep.onChange := updateRoomConfigOkBtn;

		curY := curY + 24;

        //CreateLabel(frm, secondRowOffset+10, 10+curY, 'test');
        descriptionButton := CreateButton(frm, secondRowOffset+10, curY, 'Set Descriptions...');
        descriptionButton.onclick := showDescriptionEditDialog;
        // currentUpgradeDescriptionData: TJsonObject;

		curY := curY + 34;
		// test

		//CreateLabel();
		resourceGroup := CreateGroup(frm, 10, curY, 290, 88, 'Resources*');
		resourceGroup.Name := 'resourceGroup';

		resourceBox := CreateListBox(resourceGroup, 8, 16, 200, 72, nil);
		resourceBox.Name := 'resourceBox';
        resourceBox.Multiselect := true;

		resourceBox.ondblclick := editResourceHandler;
        setupMenu(resourceBox);
        resourceBox.OnKeyDown := listboxKeyPressHandler;

		resourceAddBtn := CreateButton(resourceGroup, 210, 16, 'Add');
		resourceEdtBtn := CreateButton(resourceGroup, 210, 40, 'Edit');
		resourceRemBtn := CreateButton(resourceGroup, 210, 64, 'Remove');

		resourceAddBtn.Width := 60;
		resourceEdtBtn.Width := 60;
		resourceRemBtn.Width := 60;

		resourceAddBtn.onclick := addResourceHandler;
		resourceEdtBtn.onclick := editResourceHandler;
		resourceRemBtn.onclick := remResourceHandler;

		//
		roomFuncsGroup := CreateGroup(frm, 300, curY, 290, 88, 'Room Functions');
        roomFuncsGroup.Name := 'roomFuncsGroup';

		roomFuncsBox := CreateListBox(roomFuncsGroup, 8, 16, 200, 72, nil);
		roomFuncsBox.Name := 'roomFuncsBox';
		roomFuncsBox.Multiselect := true;
        setupMenu(roomFuncsBox);
        roomFuncsBox.OnKeyDown := listboxKeyPressHandler;

		roomFuncAddBtn := CreateButton(roomFuncsGroup, 210, 16, 'Add');
		roomFuncRemBtn := CreateButton(roomFuncsGroup, 210, 40, 'Remove');

		roomFuncAddBtn.Width := 60;
		roomFuncRemBtn.Width := 60;

		roomFuncAddBtn.onclick := addRoomFuncHandler;
		roomFuncRemBtn.onclick := remRoomFuncHandler;
		//
		curY := curY + 100;
		// layouts
		layoutsGroup := CreateGroup(frm, 10, curY, 580, 88, 'Layouts');
		layoutsGroup.Name := 'layoutsGroup';
		layoutsBox := CreateListBox(layoutsGroup, 8, 16, 490, 72, nil);
		layoutsBox.Name := 'layoutsBox';
		layoutsBox.ondblclick := editLayoutHandler;
		layoutsBox.Multiselect := true;
		setupMenu(layoutsBox);
        layoutsBox.OnKeyDown := listboxKeyPressHandler;

		layoutsAddBtn := CreateButton(layoutsGroup, 500, 16, 'Add');
		layoutsEdtBtn := CreateButton(layoutsGroup, 500, 40, 'Edit');
		layoutsRemBtn := CreateButton(layoutsGroup, 500, 64, 'Remove');

		layoutsAddBtn.Width := 60;
		layoutsEdtBtn.Width := 60;
		layoutsRemBtn.Width := 60;

		layoutsAddBtn.onclick := addLayoutHandler;
		layoutsEdtBtn.onclick := editLayoutHandler;
		layoutsRemBtn.onclick := remLayoutHandler;


		//layoutsBox: TListBox;
		//layoutsAddBtn, layoutsRemBtn, layoutsEdtBtn: TButton;

		curY := curY + 100;
		doRegisterCb := CreateCheckbox(frm, 10, curY, 'Register Room Upgrade');
		doRegisterCb.checked := true;
		curY := curY + 20;

		//curY := curY + 136;
		btnOk := CreateButton(frm, 220, curY, 'OK');
		btnOk.ModalResult := mrYes;
		btnOk.Name := 'btnOk';
		btnOk.Default := true;

		btnCancel := CreateButton(frm, 295	, curY, 'Cancel');
		btnCancel.ModalResult := mrCancel;

		btnOk.Width := 75;
		btnCancel.Width := 75;

        currentUpgradeDescriptionData := TJsonObject.create;

        // update fields if updating
        if(assigned(existingElem)) then begin
            doRegisterCb.checked := false;
            doRegisterCb.enabled := false;

            inputPrefix.Text := findEditorIdPrefix(existingElem);

            inputName.Text := GetElementEditValues(existingElem, 'FULL');
            modelStrMisc := GetElementEditValues(existingElem, 'Model\MODL');
            selectMiscModel.ItemIndex := getModelArrayIndex(modelStrMisc, selectMiscModel.Items);

            inputDuration.Text := floatToStr(getScriptPropDefault(existingMiscScript, 'Duration', 24.0));

            actionGroup := getScriptProp(existingMiscScript, 'DepartmentHQActionGroup');

            setItemIndexByForm(selectActionGroup, actionGroup);

            upgradeSlot := getScriptProp(existingMiscScript, 'TargetUpgradeSlot');

            setItemIndexByForm(selectUpgradeSlot, upgradeSlot);

            targetDepartment := WinningOverrideOrSelf(getScriptProp(existingMiscScript, 'NewDepartmentOnCompletion'));
            if(assigned(targetDepartment)) then begin
                setItemIndexByForm(selectDepartment, targetDepartment);
            end;

            fillSlotsFromExisting(extraSlotsBox.Items, existingMiscScript);

            if(assigned(existingActi)) then begin
                modelStr := GetElementEditValues(existingActi, 'Model\MODL');
                selectModel.ItemIndex := getModelArrayIndex(modelStr, selectModel.Items);
            end;


            // now the hard parts
            fillResourceItemsFromExisting(resourceBox, existingMiscScript);
            fillRoomFunctionsFromExisting(roomFuncsBox, existingMiscScript);
            fillLayoutsFromExisting(layoutsBox, existingMiscScript);
            fillDescriptionDataFromExisting(existingCobj, existingMiscScript);

            // this will repopulate the submenu dropdown
            roomUpgradeTypeChanged(btnOk);

            // do the checkboxes after that change handler, so that the room type changer doesn't unset them
            assignDepAtStart.Checked    := getScriptPropDefault(existingMiscScript, 'bAssignDepartmentToRoomAtStartOfAction', assignDepAtStart.Checked);
            assignDepAtEnd.Checked      := getScriptPropDefault(existingMiscScript, 'bAssignDepartmentToRoomAtEndOfAction', assignDepAtEnd.Checked);
            disableClutter.Checked      := getScriptPropDefault(existingMiscScript, 'bDisableClutter_OnCompletion', disableClutter.Checked);
            disableGarbarge.Checked     := getScriptPropDefault(existingMiscScript, 'bDisableGarbage_OnCompletion', disableGarbarge.Checked);
            defaultConstMarkers.Checked := getScriptPropDefault(existingMiscScript, 'bUseDefaultConstructionMarkers', defaultConstMarkers.Checked);
            realTimeTimer.Checked       := getScriptPropDefault(existingMiscScript, 'RealTimeTimer', realTimeTimer.Checked);

            // find the cobj keyword, aka submenu
            fillCobjKeywordFromExisting(selectCobjKeyword, existingCobj);
        end else begin
            // new object creation
            roomUpgradeTypeChanged(btnOk);
        end;
        showRoomUpradeDialog2UpdateOk(btnOk);



		resultCode := frm.ShowModal();
		if(resultCode = mrYes) then begin

			globalNewFormPrefix := trim(inputPrefix.text);

			// get all the data
			modelStr :=  '';
			if(selectModel.ItemIndex > 0) then begin
				modelStr := selectModel.Items[selectModel.ItemIndex];
				if(not ResourceExists(modelStr)) then begin
					modelStr := 'Meshes\AutoBuildPlots\Markers\Visible\Animation\' + modelStr;
				end;
				// if(strStartsWithCI(curRes, 'Meshes\AutoBuildPlots\Markers\Visible\Animation\')) then begin
			end;

			modelStrMisc := '';
			if(selectMiscModel.ItemIndex > 0) then begin
				modelStrMisc := selectMiscModel.Items[selectMiscModel.ItemIndex];
				if(not ResourceExists(modelStrMisc)) then begin
					modelStrMisc := 'Meshes\SS2C2\Interface\GNNRoomShapes\' + modelStrMisc;
				end;
				// if(strStartsWithCI(curRes, 'Meshes\AutoBuildPlots\Markers\Visible\Animation\')) then begin
			end;

			targetDepartment := nil;
			if(selectDepartment.ItemIndex > 0) then begin
				targetDepartment := ObjectToElement(selectDepartment.Items.Objects[selectDepartment.ItemIndex]);
			end;

            cobjKeyword := ObjectToElement(selectCobjKeyword.Items.Objects[selectCobjKeyword.ItemIndex]);


			upgradeName := trim(inputName.Text);
			upgradeDuration := tryToParseFloat(inputDuration.Text);
			upgradeSlot := ObjectToElement(currentListOfUpgradeSlots.Objects[selectUpgradeSlot.ItemIndex]);

			actionGroup := ObjectToElement(selectActionGroup.Items.Objects[selectActionGroup.ItemIndex]);

            mechanicsDescr := currentUpgradeDescriptionData.S['mechanicsDesc'];
            if(mechanicsDescr = '') then begin
                mechanicsDescr := generateUpgradeDescription(upgradeDuration, roomFuncsBox.Items);
            end;

			roomUpgradeMisc := createRoomUpgradeMisc(
				existingElem,
				targetRoomConfig,
				upgradeName,
				modelStrMisc,
				upgradeSlot,
				assignDepAtStart.Checked,
				assignDepAtEnd.Checked,
				defaultConstMarkers.Checked,
				disableClutter.Checked,
				disableGarbarge.Checked,
				realTimeTimer.Checked,
				upgradeDuration,
				targetDepartment,
				resourceBox.Items,
				roomFuncsBox.Items,
				layoutsBox.Items,
				actionGroup,
                selectActionGroup.ItemIndex,
                extraSlotsBox.Items,
                trim(currentUpgradeDescriptionData.S['designerName']),
                trim(currentUpgradeDescriptionData.S['designDesc'])
			);

            cobjSfx := nil;

            // special hack: if cobjKeyword is SS2_WorkshopMenu_HQ_Administration_Decorate, then use the sfx SS2_SFX_HQProjectType_Administration_Decorate
            if(isSameForm(cobjKeyword, SS2_WorkshopMenu_HQ_Administration_Decorate)) then begin
                cobjSfx := SS2_SFX_HQProjectType_Administration_Decorate;
            end;

            AddMessage('Selected keyword is '+EditorID(cobjKeyword));
            createRoomUpgradeActivatorsAndCobjs(
                actiData,
                roomUpgradeMisc,
                targetHQ,
                upgradeName,
                shapeKeywordBase,
                modelStr,
                resourceBox.Items,
                upgradeDuration,
                ArtObjEdid,
                cobjKeyword,
                selectActionGroup.ItemIndex,
                mechanicsDescr,
                cobjSfx
            );

            if(actiData <> nil) then begin
                actiData.free();
                actiData := nil;
            end;

			if(doRegisterCb.checked) then begin
				// register
				AddMessage('Registering Room Upgrade');
				registerAddonContent(targetFile, roomUpgradeMisc, SS2_FLID_HQActions);
			end;
			AddMessage('Room Upgrade generation complete!');
		end;


		// cleanup objects?
        currentUpgradeDescriptionData.free();

		freeStringListObjects(resourceBox.Items);
		freeStringListObjects(layoutsBox.Items);

		currentListOfUpgradeSlots.free();
		modelList.free();
		departmentList.free();
		frm.free();
	end;

    procedure showTechResearchDialog(existingElem: IInterface);
	var
        frm: TForm;
		btnOk, btnCancel: TButton;
		resultCode, curY, secondRowOffset, thirdRowOffset: integer;

		selectMiscModel, selectModel, selectActionGroup, selectCobjKeyword, selectPutDownSound: TComboBox;
		assignDepAtEnd, assignDepAtStart, disableClutter, disableGarbarge, defaultConstMarkers, realTimeTimer, completableCheckbox: TCheckBox;
		doRegisterCb: TCheckBox;
		departmentList, modelList, modelListMisc: TStringList;
		inputName, inputPrefix, inputDuration: TEdit; ///Duration: Float - default to 24

		resourceGroup: TGroupBox;
		resourceBox: TListBox;
		resourceAddBtn, resourceRemBtn, resourceEdtBtn, descriptionButton: TButton;

		modelStr, modelStrMisc, upgradeName, windowCaption, shapeKeywordBase, MiscModelFilename, artObjEdid, mechanicsDescr: string;
		targetDepartment: IInterface;

		roomUpgradeMisc, roomUpgradeActi: IInterface;
		upgradeDuration: float;

		roomShapeKeyword, upgradeSlot, actionGroup, putDownSound: IInterface;

        // existing stuff
        existingMiscScript, existingActi, existingActiScript, existingCobj, cobjKeyword: IInterface;

        modelIndex: integer;

        actiData : TJsonObject;

        descriptionInput: TCustomMemo;
	begin
		// load the slots for what we have
        //currentListOfUpgradeSlots := getRoomUpgradeSlots(targetHQ, targetRoomConfig);

		secondRowOffset := 300;
        actiData := nil;
        windowCaption := 'Generating Tech Research/Other';
        if(assigned(existingElem)) then begin
            windowCaption := 'Updating Tech Research/Other';

            existingMiscScript := findScriptInElementByNameCached(existingElem, 'SimSettlementsV2:HQ:Library:MiscObjects:RequirementTypes:HQAction');

            actiData := findRoomUpgradeActivatorsAndCobjs(existingElem);

            existingActi := nil;
            existingCobj := nil;

            // try to find the acti model
            if (actiData.O['1'].S['acti'] <> '') then begin
                existingActi := AbsStrToForm(actiData.O['1'].S['acti']);
            end else begin
                if (actiData.O['2'].S['acti'] <> '') then begin
                    existingActi := AbsStrToForm(actiData.O['2'].S['acti']);
                end else begin
                    if (actiData.O['3'].S['acti'] <> '') then begin
                        existingActi := AbsStrToForm(actiData.O['3'].S['acti']);
                    end;
                end;
            end;

            if (actiData.O['1'].S['cobj'] <> '') then begin
                existingCobj := AbsStrToForm(actiData.O['1'].S['cobj']);
            end else begin
                if (actiData.O['2'].S['cobj'] <> '') then begin
                    existingCobj := AbsStrToForm(actiData.O['2'].S['cobj']);
                end else begin
                    if (actiData.O['3'].S['cobj'] <> '') then begin
                        existingCobj := AbsStrToForm(actiData.O['3'].S['cobj']);
                    end;
                end;
            end;

            if(assigned(existingActi)) then begin
                // try to find the acti, too
                existingActi := findRoomUpgradeActivator(existingElem);
            end;

        end;

        //roomShapeKeyword := getRoomShapeKeywordFromConfig(targetRoomConfig);
        //shapeKeywordBase := getRoomShapeUniquePart(EditorID(roomShapeKeyword));

        MiscModelFilename := '';//shapeKeywordBase+'.nif';
        ArtObjEdid := '';//'SS2C2_AO_RoomShape_'+shapeKeywordBase;

		frm := CreateDialog(windowCaption, 620, 400);
		frm.Name := 'techResearchDialog2';
		curY := 0;
		//if(not assigned(existingElem)) then begin
        CreateLabel(frm, 10, 10+curY, 'HQ: '+EditorID(targetHQ)+'.');
        //CreateLabel(frm, 10, 28+curY, 'Room Config: '+EditorID(targetRoomConfig));
		//end;

		curY := curY + 46;

		CreateLabel(frm, 10, 10+curY, 'Name:*');
		inputName := CreateInput(frm, 100, 8+curY, '');
		inputName.Name := 'inputName';
		inputName.Text := '';
		inputName.width := 200;
		inputName.onChange := showTechResearchDialog2UpdateOk;

		CreateLabel(frm, secondRowOffset+10, 10+curY, 'EditorID Prefix:*');
		inputPrefix := CreateInput(frm, secondRowOffset+100, 8+curY, '');
		inputPrefix.Name := 'inputPrefix';
		inputPrefix.Text := '';
		inputPrefix.width := 200;
		inputPrefix.onChange := showTechResearchDialog2UpdateOk;


		curY := curY + 24;

		modelListMisc := prependNoneEntry(listModelsMisc);
		modelList := prependNoneEntry(listModels);
		//selectActionGroup
        // this is different now
		CreateLabel(frm, 10, 10+curY, 'Action Type:*');

		selectActionGroup := CreateComboBox(frm, 100, 8+curY, 500, nil);
		selectActionGroup.Style := csDropDownList;
		selectActionGroup.Name := 'selectActionGroup';
		selectActionGroup.ItemIndex := -1;
		selectActionGroup.Items := listTechActionTypes;

        //fillObjectTypeActionGroups(targetHQ, selectActionGroup);
		//selectActionGroup.onChange := roomUpgradeTypeChanged;

        curY := curY + 24;
		CreateLabel(frm, 10, 10+curY, 'Misc Model:');
		selectMiscModel := CreateComboBox(frm, 100, 8+curY, 500, modelListMisc);
		selectMiscModel.Style := csDropDownList;
		selectMiscModel.Name := 'selectMiscModel';
		selectMiscModel.ItemIndex := 0;

		curY := curY + 24;
		CreateLabel(frm, 10, 10+curY, 'Activator Model:');
		selectModel := CreateComboBox(frm, 100, 8+curY, 500, modelList);
		selectModel.Style := csDropDownList;
		selectModel.Name := 'selectModel';
		selectModel.ItemIndex := 0;

        //Stand_Hammer_Vertical.nif
        modelIndex := modelList.indexOf('Stand_Hammer_Vertical.nif');
        if(modelIndex > -1) then begin
            selectModel.ItemIndex := modelIndex;
        end;

        //modelIndex := modelListMisc.indexOf(MiscModelFilename);
        //if(modelIndex > -1) then begin
            selectMiscModel.ItemIndex := modelIndex;
        //end;

		curY := curY + 24;
        CreateLabel(frm, 10, 10+curY, 'Submenu:*');
        selectCobjKeyword := CreateComboBox(frm, 100, 8+curY, 200, listKeywordsTech);
		selectCobjKeyword.Style := csDropDownList;
		selectCobjKeyword.Name := 'selectCobjKeyword';
		selectCobjKeyword.onchange := showTechResearchDialog2UpdateOk;
        //curY := curY + 24;

        CreateLabel(frm, secondRowOffset+10, 10+curY, 'Putdown sound:');
        selectPutDownSound := CreateComboBox(frm, secondRowOffset+100, 8+curY, 200, listPutDownSounds);
		selectPutDownSound.Style := csDropDownList;
		selectPutDownSound.Name := 'selectPutDownSound';



        secondRowOffset := 170;
        thirdRowOffset := 340;

		// selectUpgradeSlot.onChange := updateRoomUpgrade1OkBtn;
		curY := curY + 42;
		realTimeTimer:= CreateCheckbox(frm, 10, curY, 'Real-Time Timer');
		realTimeTimer.Checked := false;

        completableCheckbox := CreateCheckbox(frm, secondRowOffset+10, curY, 'Completable');
        completableCheckbox.Checked := false;

		//curY := curY + 24;

        secondRowOffset := 300;

		CreateLabel(frm, thirdRowOffset+10, curY, 'Duration (hours):*');
		inputDuration := CreateInput(frm, thirdRowOffset+140, curY-2, '24.0');
		inputDuration.width := 120;
		inputDuration.Name := 'inputDuration';
		inputDuration.Text := '24.0';
		inputDuration.onChange := showTechResearchDialog2UpdateOk;

		curY := curY + 24;


		//CreateLabel();
		resourceGroup := CreateGroup(frm, 10, curY, 290, 88, 'Resources*');
		resourceGroup.Name := 'resourceGroup';

		resourceBox := CreateListBox(resourceGroup, 8, 16, 200, 72, nil);
		resourceBox.Name := 'resourceBox';
        resourceBox.Multiselect := true;

		resourceBox.ondblclick := editResourceHandler;
        setupMenu(resourceBox);
        resourceBox.OnKeyDown := listboxKeyPressHandler;

		resourceAddBtn := CreateButton(resourceGroup, 210, 16, 'Add');
		resourceEdtBtn := CreateButton(resourceGroup, 210, 40, 'Edit');
		resourceRemBtn := CreateButton(resourceGroup, 210, 64, 'Remove');

		resourceAddBtn.Width := 60;
		resourceEdtBtn.Width := 60;
		resourceRemBtn.Width := 60;

		resourceAddBtn.onclick := addResourceHandler;
		resourceEdtBtn.onclick := editResourceHandler;
		resourceRemBtn.onclick := remResourceHandler;

        CreateLabel(frm, secondRowOffset+10, curY, 'Mechanics description:');
        descriptionInput := CreateMultilineInput(frm, secondRowOffset+10, curY+16, 290, 80, '');


		//layoutsBox: TListBox;
		//layoutsAddBtn, layoutsRemBtn, layoutsEdtBtn: TButton;

		curY := curY + 100;
		doRegisterCb := CreateCheckbox(frm, 10, curY, 'Register');
		doRegisterCb.checked := true;
		curY := curY + 20;

		//curY := curY + 136;
		btnOk := CreateButton(frm, 220, curY, 'OK');
		btnOk.ModalResult := mrYes;
		btnOk.Name := 'btnOk';
		btnOk.Default := true;

		btnCancel := CreateButton(frm, 295	, curY, 'Cancel');
		btnCancel.ModalResult := mrCancel;

		btnOk.Width := 75;
		btnCancel.Width := 75;

        currentUpgradeDescriptionData := TJsonObject.create;


        // update fields if updating
        if(assigned(existingElem)) then begin

            doRegisterCb.checked := false;
            doRegisterCb.enabled := false;

            inputPrefix.Text := findEditorIdPrefix(existingElem);

            inputName.Text := GetElementEditValues(existingElem, 'FULL');
            modelStrMisc := GetElementEditValues(existingElem, 'Model\MODL');
            selectMiscModel.ItemIndex := getModelArrayIndex(modelStrMisc, selectMiscModel.Items);

            completableCheckbox.Checked := getScriptPropDefault(existingMiscScript, 'Completable', completableCheckbox.Checked);
            realTimeTimer.Checked       := getScriptPropDefault(existingMiscScript, 'RealTimeTimer', realTimeTimer.Checked);

            inputDuration.Text := floatToStr(getScriptPropDefault(existingMiscScript, 'Duration', 24.0));

            // actionGroup := getScriptProp(existingMiscScript, 'DepartmentHQActionGroup'); // this doesn't work

            setItemIndexByForm(selectActionGroup, actionGroup);
            selectActionGroup.enabled := false;


            if(assigned(existingActi)) then begin
                modelStr := GetElementEditValues(existingActi, 'Model\MODL');
                selectModel.ItemIndex := getModelArrayIndex(modelStr, selectModel.Items);
            end;


            // find the cobj

            fillCobjKeywordFromExisting(selectCobjKeyword, existingCobj);
            //selectCobjKeyword

            // now the hard parts
            fillResourceItemsFromExisting(resourceBox, existingMiscScript);

            if(assigned(existingCobj)) then begin
                descriptionInput.Text := getElementEditValues(existingCobj, 'DESC');

                putDownSound := pathLinksTo(existingCobj, 'ZNAM');

                setItemIndexByForm(selectPutDownSound, putDownSound);
            end;

        end;

        //roomUpgradeTypeChanged(btnOk);
        showTechResearchDialog2UpdateOk(btnOk);

		resultCode := frm.ShowModal();

		if(resultCode = mrYes) then begin

			globalNewFormPrefix := trim(inputPrefix.text);

			// get all the data
			modelStr :=  '';
			if(selectModel.ItemIndex > 0) then begin
				modelStr := selectModel.Items[selectModel.ItemIndex];
				if(not ResourceExists(modelStr)) then begin
					modelStr := 'Meshes\AutoBuildPlots\Markers\Visible\Animation\' + modelStr;
				end;
				// if(strStartsWithCI(curRes, 'Meshes\AutoBuildPlots\Markers\Visible\Animation\')) then begin
			end;


			modelStrMisc := '';
			if(selectMiscModel.ItemIndex > 0) then begin
				modelStrMisc := selectMiscModel.Items[selectMiscModel.ItemIndex];
				if(not ResourceExists(modelStrMisc)) then begin
					modelStrMisc := 'Meshes\SS2C2\Interface\GNNRoomShapes\' + modelStrMisc;
				end;
				// if(strStartsWithCI(curRes, 'Meshes\AutoBuildPlots\Markers\Visible\Animation\')) then begin
			end;


            cobjKeyword := ObjectToElement(selectCobjKeyword.Items.Objects[selectCobjKeyword.ItemIndex]);


			upgradeName := trim(inputName.Text);
			upgradeDuration := tryToParseFloat(inputDuration.Text);
			//upgradeSlot := ObjectToElement(currentListOfUpgradeSlots.Objects[selectUpgradeSlot.ItemIndex]);

            if(selectActionGroup.ItemIndex >= 0) then begin
                actionGroup := ObjectToElement(selectActionGroup.Items.Objects[selectActionGroup.ItemIndex]);
            end else begin
                actionGroup := nil;
            end;

            if(selectPutDownSound.ItemIndex >= 0) then begin
                putDownSound := ObjectToElement(selectPutDownSound.Items.Objects[selectPutDownSound.ItemIndex]);
            end else begin
                putDownSound := nil;
            end;

            roomUpgradeMisc := createTechResearchMisc(
                existingElem,
                //targetRoomConfig,
                upgradeName,
				modelStrMisc,
                completableCheckbox.Checked,
                realTimeTimer.Checked,
                upgradeDuration,
                resourceBox.Items,
                actionGroup
            );

            // AddMessage('cobjKeyword = '+EditorID(cobjKeyword)+' '+IntToStr(selectCobjKeyword.ItemIndex));

            createRoomUpgradeActivatorsAndCobjs(
                actiData,
                roomUpgradeMisc,
                targetHQ,
                upgradeName,
                '',
                modelStr,
                resourceBox.Items,
                upgradeDuration,
                ArtObjEdid,
                cobjKeyword,
                2,
                trim(descriptionInput.Text),
                putDownSound
            );

            if(actiData <> nil) then begin
                actiData.free();
                actiData := nil;
            end;

			if(doRegisterCb.checked) then begin
				// register
				AddMessage('Registering Room Upgrade');
				registerAddonContent(targetFile, roomUpgradeMisc, SS2_FLID_HQActions);
			end;
			AddMessage('Room Upgrade generation complete!');
		end;


		// cleanup objects?
        currentUpgradeDescriptionData.free();

		freeStringListObjects(resourceBox.Items);
//		freeStringListObjects(layoutsBox.Items);

		//currentListOfUpgradeSlots.free();
		modelList.free();
//		departmentList.free();
		frm.free();
	end;

    function getRoomConfigEdidPart(configMisc: IInterface): string;
	var
		edid, confName: string;
	begin
		edid := EditorID(configMisc);
		Result := regexReplace(edid, '[^_]+_HQ[^_]*_Action_AssignRoomConfig_', '');
	end;

	function createRoomLayout(existingElem, hq, roomConfig: IInterface; layoutName, csvPath, upgradeNameSpaceless, slotNameSpaceless: string; upgradeSlot, descriptionMsg, designerMisc: IInterface): IInterface;
	var
		resultEdid, layoutNameSpaceless, curLine, curEditorId, curFileName, slotEdid: string;
		spawnData: TJsonObject;
		csvLines, csvCols, spawnObj: TStringList;
		posX, posY, posZ, rotX, rotY, rotZ, i: integer;
		curForm, resultScript: IInterface;
		curFormID: cardinal;
		isResourceObject: boolean;
		arrayToUse, resourceObjArray, nonResObjArray: IInterface;
		bRelativePositioning: boolean;

		curSpawnObj, itemPosVector, itemRotVector, rotatedData: TJsonObject;
		itemScale: float;

		slotKw, slotScript: IInterface;
	begin
        if(not assigned(existingElem)) then begin
            layoutNameSpaceless := cleanStringForEditorID(layoutName);

            resultEdid := generateEdid('HQRoomLayout_', findHqNameShort(hq)+'_'+getRoomConfigEdidPart(roomConfig)+'_'+upgradeNameSpaceless+'_'+slotNameSpaceless+'_'+layoutNameSpaceless);
            Result := getCopyOfTemplateOA(targetFile, SS2_HQRoomLayout_Template, resultEdid);
        end else begin
            Result := getOrCreateElementOverride(existingElem, targetFile);
        end;

		resultScript := getScript(Result, 'SimSettlementsV2:HQ:Library:Weapons:HQRoomLayout');

		SetElementEditValues(Result, 'FULL', layoutName);

		// put in the slot KW
		slotKw := findSlotKeywordFromSlotMisc(upgradeSlot);

        slotEdid := EditorID(upgradeSlot);
        if(Pos('decoration', LowerCase(slotEdid)) > 0) then begin
            // Special hack: if the selected slot is a 'Decoration', also use SS2_UsageRequirements_PerformanceSettingOn_Clutter
            // put this into 'Requirements' on the layout script
            setScriptProp(resultScript, 'Requirements', SS2_UsageRequirements_PerformanceSettingOn_Clutter);
        end;

		setScriptProp(resultScript, 'TagKeyword', slotKw);
		//setScriptProp(resultScript, 'workshopRef', hq);
        setUniversalForm(resultScript, 'workshopRef', hq);

		// now, the hard part
		spawnData := TJsonObject.create();

        if(assigned(descriptionMsg)) then begin
            setScriptProp(resultScript, 'InformationMessage', descriptionMsg);
        end else begin
            clearScriptProp(resultScript, 'InformationMessage');
        end;

        if(assigned(designerMisc)) then begin
            setScriptProp(resultScript, 'DesignerNameHolder', designerMisc);
        end else begin
            clearScriptProp(resultScript, 'DesignerNameHolder');
        end;

        // property descriptionMsg, designerMisc

        if (csvPath = '') or (not FileExists(csvPath)) then begin
            exit;
        end;



		bRelativePositioning := false;
		// load and parse CSV
		csvLines := TStringList.create;
		csvLines.LoadFromFile(csvPath);
		for i:=1 to csvLines.count-1 do begin
			curLine := trim(csvLines[i]);
			if(curLine = '') then begin
				continue;
			end;

			//  1,2,3 = pos
			//  4,5,6 = rot
			//  7 = scale
			//  8 = fExtraDataFlag
			//  9 = iFormID (as alternative to ObjectForm)
			// 10 = sPluginName (as alternative to ObjectForm)



			csvCols := TStringList.create;

			csvCols.Delimiter := ',';
			csvCols.StrictDelimiter := TRUE;
			csvCols.DelimitedText := curLine;

            if (csvCols.count < 8) then begin
                AddMessage('Line "'+curLine+'" is not valid, skipping');
				csvCols.Free;
				continue;
            end;

			 // pos, rot, scale
			if (csvCols.Strings[0] = '') or
				(csvCols.Strings[1] = '') or
				(csvCols.Strings[2] = '') or
				(csvCols.Strings[3] = '') or
				(csvCols.Strings[4] = '') or
				(csvCols.Strings[5] = '') or
				(csvCols.Strings[6] = '') or
				(csvCols.Strings[7] = '') then begin
				AddMessage('Line "'+curLine+'" is not valid, skipping');
				csvCols.Free;
				continue;
			end;

			curEditorId := trim(csvCols[0]);

			if(strStartsWith(curEditorId,'SS2_C2_Marker_HQRoomExportHelper')) then begin
				spawnData.O['offset'].O['pos'] := newVector(StrToFloat(csvCols.Strings[1]), StrToFloat(csvCols.Strings[2]), StrToFloat(csvCols.Strings[3]));
				spawnData.O['offset'].O['rot'] := newVector(StrToFloat(csvCols.Strings[4]), StrToFloat(csvCols.Strings[5]), StrToFloat(csvCols.Strings[6]));
				bRelativePositioning := true;
			end else begin
				curForm := FindObjectByEdidWithSuffix(curEditorId);
				if(not assigned(curForm)) then begin
					// check other stuff
					if (csvCols.count < 10) then begin
						AddMessage('Failed to find form '+curEditorId+', and no FormID/Filename specified');
						continue;
					end;

					if (
						(trim(csvCols.Strings[9]) = '') or (trim(csvCols.Strings[10]) = '')
					) then begin
						AddMessage('Failed to find form '+curEditorId+', and no FormID/Filename specified');
						continue;
					end;
				end;

				spawnObj := spawnData.A['spawns'].AddObject();

				if(assigned(curForm)) then begin
					spawnObj.S['Form'] := FormToAbsStr(curForm);
				end;

				spawnObj.O['pos'] := newVector(StrToFloat(csvCols.Strings[1]), StrToFloat(csvCols.Strings[2]), StrToFloat(csvCols.Strings[3]));
				spawnObj.O['rot'] := newVector(StrToFloat(csvCols.Strings[4]), StrToFloat(csvCols.Strings[5]), StrToFloat(csvCols.Strings[6]));
				spawnObj.F['scale'] := StrToFloat(csvCols.Strings[7]);

				if(csvCols.count > 8) then begin
					if(csvCols.Strings[8] <> '') then begin
						spawnObj.F['extraData'] := StrToFloat(csvCols.Strings[8]);
					end;

					if(csvCols.count > 10) then begin
						if (csvCols.Strings[9] <> '') and (csvCols.Strings[10] <> '') then begin
							spawnObj.S['extFormId'] := csvCols.Strings[9];
							spawnObj.S['extFileName'] := csvCols.Strings[10];

							curFormID := IntToStr('$'+csvCols.Strings[9]);
							curFileName := csvCols.Strings[10];
						end;
					end;
				end;

				isResourceObject := false;

				if(assigned(curForm)) then begin
					isResourceObject := isResourceObject_elem(curForm);
				end else begin
					isResourceObject := isResourceObject_id(curFileName, curFormID);
				end;

				spawnObj.B['isResourceObject'] := isResourceObject;

			end;

			csvCols.free();
		end;


		// now everything should be parsed
		if(bRelativePositioning) then begin
			hasRelativeCoordinateLayout   := true;
		end else begin
			hasNonRelativeCoordinateLayout:= true;
		end;

		setScriptProp(resultScript, 'bUseRelativeCoordinates', bRelativePositioning);

        if(assigned(existingElem)) then begin
            // clear these if they exist
            clearScriptProp(resultScript, 'WorkshopResources');
            clearScriptProp(resultScript, 'NonResourceObjects');
        end;

		for i:=0 to spawnData.A['spawns'].count-1 do begin
			spawnObj := spawnData.A['spawns'].O[i];
			isResourceObject := spawnObj.B['isResourceObject'];

			if(isResourceObject) then begin
				if(not assigned(resourceObjArray)) then begin
					resourceObjArray   := getOrCreateScriptPropArrayOfStruct(resultScript, 'WorkshopResources');
				end;
				arrayToUse := resourceObjArray;
			end else begin
				if(not assigned(nonResObjArray)) then begin
					nonResObjArray   := getOrCreateScriptPropArrayOfStruct(resultScript, 'NonResourceObjects');
				end;
				arrayToUse := nonResObjArray;
			end;

			if(bRelativePositioning) then begin
				itemPosVector := newVector(spawnObj.O['pos'].F['x'], spawnObj.O['pos'].F['y'], spawnObj.O['pos'].F['z']);
				itemRotVector := newVector(spawnObj.O['rot'].F['x'], spawnObj.O['rot'].F['y'], spawnObj.O['rot'].F['z']);

				rotatedData := ConvertAbsoluteCoordinatesToBaseRelative(spawnData.O['offset'].O['pos'], spawnData.O['offset'].O['rot'], itemPosVector, itemRotVector);

				spawnObj.O['pos'].F['x'] := rotatedData.O['pos'].F['x'];
				spawnObj.O['pos'].F['y'] := rotatedData.O['pos'].F['y'];
				spawnObj.O['pos'].F['z'] := rotatedData.O['pos'].F['z'];
				spawnObj.O['rot'].F['x'] := rotatedData.O['rot'].F['x'];
				spawnObj.O['rot'].F['y'] := rotatedData.O['rot'].F['y'];
				spawnObj.O['rot'].F['z'] := rotatedData.O['rot'].F['z'];
				// curSpawnObj.F['scale']:= spawnObj.F['scale'];

				rotatedData.free();
				itemRotVector.free();
				itemPosVector.free();
			end;

			appendSpawn(spawnObj, arrayToUse);
		end;

		csvLines.free();

		spawnData.free();
	end;

	procedure appendSpawn(itemData: TJsonObject; targetArray: IInterface);
	var
		newStruct, formElem: IInterface;
		loFormId: cardinal;
	begin
		formElem := nil;
		if(itemData.S['Form'] <> '') then begin
			formElem := AbsStrToForm(itemData.S['Form']);
		end;

		newStruct := appendStructToProperty(targetArray);

		loFormId := 0;
		if(itemData.S['extFormId'] <> '') then begin
			loFormId := StrToInt('$'+itemData.S['extFormId']);
		end;


		setUniversalFormProperty(newStruct, formElem, loFormId, itemData.S['extFileName'], 'ObjectForm', 'iFormID', 'sPluginName');


		setStructMemberDefault(newStruct, 'fPosX', itemData.O['pos'].F['x'], 0.0);
		setStructMemberDefault(newStruct, 'fPosY', itemData.O['pos'].F['y'], 0.0);
		setStructMemberDefault(newStruct, 'fPosZ', itemData.O['pos'].F['z'], 0.0);

		setStructMemberDefault(newStruct, 'fAngleX', itemData.O['rot'].F['x'], 0.0);
		setStructMemberDefault(newStruct, 'fAngleY', itemData.O['rot'].F['y'], 0.0);
		setStructMemberDefault(newStruct, 'fAngleZ', itemData.O['rot'].F['z'], 0.0);

		setStructMemberDefault(newStruct, 'fScale', itemData.F['scale'], 1.0);
		setStructMemberDefault(newStruct, 'bForceStatic', 0.0, false);
		setStructMemberDefault(newStruct, 'fExtraDataFlag', itemData.F['extraData'], 0.0);
	end;

	function getMappedResource(vrResource: IInterface; complexity: integer): IInterface;
	var
		vrFormStr, resultStr: string;
	begin
		Result := nil;
		vrFormStr := FormToAbsStr(vrResource);
		resultStr := resourceLookupTable.O[vrFormStr].S[complexity];
		if(resultStr = '') then begin
			exit;
		end;

		Result := AbsStrToForm(resultStr);
	end;

	function getResourcesGrouped(resources: TStringList; resourceComplexity: integer): TJsonObject;
	var
		i, resIndex, count, numScrap, numSupplies: integer;
		resourceData: TJsonObject;
		curResource, realResource: IInterface;
		sig, resourceStr, inputResourceId: string;
	begin
        numScrap := 0;
        numSupplies := 0;
		Result := TJsonObject.create();
		for i:=0 to resources.count-1 do begin
			resourceData := TJsonObject(resources.Objects[i]);

			count := resourceData.I['count'];

			resIndex := resourceData.I['index'];
			curResource := ObjectToElement(listRoomResources.Objects[resIndex]);

            inputResourceId := EditorID(curResource);

			sig := Signature(curResource);

			if(sig = 'AVIF') then begin
				realResource := getMappedResource(curResource, resourceComplexity);
				if(not assigned(realResource)) then begin
					AddMessage('Failed to map '+EditorID(curResource)+' to anything');
					continue;
				end;
			end else if(sig = 'MISC') then begin
				// try finding the component
				realResource := getFirstCVPA(curResource);
				if(not assigned(realResource)) then begin
					realResource := curResource;
				end;
			end else begin
				realResource := curResource;
			end;

            if(inputResourceId <> 'SS2_VirtualResource_Caps') then begin
                if(strStartsWith(inputResourceId, 'SS2_VirtualResource_Supplies_')) then begin
                    numSupplies := numSupplies + count;
                end else if(strStartsWith(inputResourceId, 'SS2_VirtualResource_')) then begin
                    numScrap := numScrap + count;
                end;
            end;

			resourceStr := FormToAbsStr(realResource);
			Result.I[resourceStr] := Result.I[resourceStr] + count;
		end;

        if(numScrap > 0) then begin
            resourceStr := FormToAbsStr(SS2_c_HQ_DailyLimiter_Scrap);
			Result.I[resourceStr] := numScrap;
        end;

        if(numSupplies > 0) then begin
            resourceStr := FormToAbsStr(SS2_c_HQ_DailyLimiter_Supplies);
			Result.I[resourceStr] := numSupplies;
        end;
	end;



    function findRoomUpgradeCOBJ(resourceComplexity: integer; acti: IInterface): IInterface;
    var
        i, curComplexity: integer;
        curRef, conditions, complexityCondition, glob: IInterface;
    begin
        for i:=0 to ReferencedByCount(acti)-1 do begin
            curRef := ReferencedByIndex(acti, i);
            if(Signature(curRef) = 'COBJ') then begin
                if(equals(PathLinksTo(curRef, 'CNAM'), acti)) then begin
                    // now check which complexity we have
                    conditions := ElementByPath(curRef, 'Conditions');
                    if(getCobjConditionValue(conditions) = resourceComplexity) then begin
                        Result := curRef;
                        exit;
                    end;
                end;
            end;
        end;

        Result := nil;
    end;

	function createRoomUpgradeCOBJ(
        existingElem: IInterface;
        edidBase, descriptionText: string;
        resourceComplexity: integer;
        acti, availableGlobal: IInterface;
        resources: TStringList;
        artObject: IInterface;
        cobjKeyword: IInterface;
        roomMode: integer;
        putDownSound: IInterface
    ): IInterface;
	var
		edid, curName: string;
		i, count, totalCount: integer;
		availCondition, complexityCondition, fvpa, component, conditions: IInterface;
		cobjResources: TJsonObject;
        sourceTemplate, srcFnam, dstFnam, kwHolder: IInterface;

	begin
        // roomMode is:
        // 0 = construction
        // 1 = upgrade
        // 2 = tech/other
        // try to find the cobj
        //Result := findRoomUpgradeCOBJ(resourceComplexity, acti);

        Result := nil;
        if(assigned(existingElem)) then begin
            Result := getOrCreateElementOverride(existingElem, targetFile);
        end;


        if(roomMode = 0) then begin
            sourceTemplate := CobjRoomConstruction_Template;
        end else begin
            sourceTemplate := CobjRoomUpgrade_Template;
        end;


        if(not assigned(Result)) then begin
            edid := shortenEdid(edidBase + '_co_' + IntToStr(resourceComplexity));

            Result := getCopyOfTemplateOA(targetFile, sourceTemplate, edid);
        end else begin
            // apply some things from the template
            // set the put down sound

            setPathLinksTo(Result, 'ZNAM', pathLinksTo(sourceTemplate, 'ZNAM'));
        end;

        if (assigned(putDownSound)) then begin
            setPathLinksTo(Result, 'ZNAM', putDownSound);
        end;

        // try to remove the FNAMs
        dstFnam := ElementByPath(Result, 'FNAM');
        // clear the prev
        for i:=0 to ElementCount(dstFnam)-1 do begin
            // sometimes this removes element 0, sometimes it doesn't
            RemoveElement(dstFnam, 0);
        end;

        kwHolder := ElementByIndex(dstFnam, 0);
        if(not assigned(kwHolder)) then begin
            kwHolder := ElementAssign(dstFnam, HighInteger, nil, False);
        end;

        // put in cobjKeyword
        SetLinksTo(kwHolder, cobjKeyword);


		SetElementEditValues(Result, 'DESC', descriptionText);

		conditions := ElementByPath(Result, 'Conditions');

		availCondition := ElementByIndex(conditions, 0);
		complexityCondition := ElementByIndex(conditions, 1);

		setPathLinksTo(availCondition, 'CTDA\Global', availableGlobal);
		setElementEditValues(complexityCondition, 'CTDA\Comparison Value', IntToStr(resourceComplexity));

		setPathLinksTo(Result, 'CNAM', acti);

		// resources
		cobjResources := getResourcesGrouped(resources, resourceComplexity);
		RemoveElement(Result, 'FVPA');
		fvpa := ensurePath(Result, 'FVPA');

        // art object
        if(assigned(artObject)) then begin
            setPathLinksTo(Result, 'ANAM', artObject);
        end;

        // SS2_c_HQ_DailyLimiter_Scrap

		for i:=0 to cobjResources.count-1 do begin
			curName := cobjResources.names[i];
			count := cobjResources.I[curName];

			//component := Add(fvpa, 'Component', true);
			component := ElementAssign(fvpa, HighInteger, nil, False);

			setPathLinksTo(component, 'Component', AbsStrToForm(curName));
			SetElementEditValues(component, 'Count', IntToStr(count));
		end;

		cobjResources.free();
	end;


    procedure createRoomUpgradeActivatorsAndCobjs(
        existingData: TJsonObject;
        roomUpgradeMisc, forHq: IInterface;
        upgradeName, roomConfigName, modelStr: string;
        resources: TStringList;
        completionTime: float;
        ArtObjEdid: string;
        cobjKeyword: IInterface;
        roomMode: integer;
        descriptionText: string;
        putDownSound: IInterface
    );
    var
        availableGlobal, artObject: IInterface;
        acti1, acti2, acti3, cobj1, cobj2, cobj3: IInterface;
        edidBase, upgradeNameSpaceless: string;
        numDays: float;
    begin
        artObject := nil;

        if(ArtObjEdid <> '') then begin
            artObject := findObjectByEdid(ArtObjEdid);
        end;

        availableGlobal := getActionAvailableGlobal(roomUpgradeMisc);
        // get the room shape



        if(roomConfigName <> '') then begin
            upgradeNameSpaceless := cleanStringForEditorID(roomConfigName+'_'+upgradeName);
        end else begin
            upgradeNameSpaceless := cleanStringForEditorID(upgradeName);
        end;
        acti1 := nil;
        acti2 := nil;
        acti3 := nil;
        cobj1 := nil;
        cobj2 := nil;
        cobj3 := nil;


        if (nil <> existingData) then begin
            if(existingData.O['1'].S['acti'] <> '') then acti1 := AbsStrToForm(existingData.O['1'].S['acti']);
            if(existingData.O['2'].S['acti'] <> '') then acti2 := AbsStrToForm(existingData.O['2'].S['acti']);
            if(existingData.O['3'].S['acti'] <> '') then acti3 := AbsStrToForm(existingData.O['3'].S['acti']);

            if(existingData.O['1'].S['cobj'] <> '') then cobj1 := AbsStrToForm(existingData.O['1'].S['cobj']);
            if(existingData.O['2'].S['cobj'] <> '') then cobj2 := AbsStrToForm(existingData.O['2'].S['cobj']);
            if(existingData.O['3'].S['cobj'] <> '') then cobj3 := AbsStrToForm(existingData.O['3'].S['cobj']);
        end;


        edidBase := globalNewFormPrefix+'HQ'+findHqNameShort(forHq)+'_BuildableAction_'+upgradeNameSpaceless;

        acti1 := createRoomUpgradeActivator(acti1, roomUpgradeMisc, forHq, upgradeName, edidBase, modelStr, RESOURCE_COMPLEXITY_MINIMAL);
        acti2 := createRoomUpgradeActivator(acti2, roomUpgradeMisc, forHq, upgradeName, edidBase, modelStr, RESOURCE_COMPLEXITY_CATEGORY);
        acti3 := createRoomUpgradeActivator(acti3, roomUpgradeMisc, forHq, upgradeName, edidBase, modelStr, RESOURCE_COMPLEXITY_FULL);

        // now the COBJs
		cobj1 := createRoomUpgradeCOBJ(cobj1, edidBase, descriptionText, RESOURCE_COMPLEXITY_MINIMAL,  acti1, availableGlobal, resources, artObject, cobjKeyword, roomMode, putDownSound);
		cobj2 := createRoomUpgradeCOBJ(cobj2, edidBase, descriptionText, RESOURCE_COMPLEXITY_CATEGORY, acti2, availableGlobal, resources, artObject, cobjKeyword, roomMode, putDownSound);
		cobj3 := createRoomUpgradeCOBJ(cobj3, edidBase, descriptionText, RESOURCE_COMPLEXITY_FULL, 	   acti3, availableGlobal, resources, artObject, cobjKeyword, roomMode, putDownSound);
    end;

	function createRoomUpgradeActivator(existingElem, roomUpgradeMisc, forHq: IInterface; upgradeName, edidBase, modelStr: string; resourceComplexity: integer): IInterface;
	var
		upgradeNameSpaceless, edid: string;
		hqManager, script: IInterface;
	begin
		hqManager := getManagerForHq(forHq);
		if(not assigned(hqManager)) then begin
			AddMessage('=== ERROR: failed to find manager for HQ');
		end;

        if(not assigned(existingElem)) then begin
            upgradeNameSpaceless := cleanStringForEditorID(upgradeName);
            edid := shortenEdid(edidBase+'_ac_'+IntToStr(resourceComplexity));
            Result := getCopyOfTemplateOA(targetFile, SS2_HQBuildableAction_Template, edid);
        end else begin
            Result := getOrCreateElementOverride(existingElem, targetFile);
        end;


		script := getScript(Result, 'SimSettlementsV2:HQ:Library:ObjectRefs:HQWorkshopItemActionTrigger');

		setScriptProp(script, 'HQAction', roomUpgradeMisc);
		setScriptProp(script, 'SpecificHQManager', hqManager);

		SetElementEditValues(Result, 'FULL', upgradeName);

		if(modelStr <> '') then begin
			ensurePath(Result, 'Model\MODL');
			SetElementEditValues(Result, 'Model\MODL', modelStr);
		end;
    end;

    function findRoomUpgradeActivator(roomUpgradeMisc: IInterface): IInterface;
	var
		upgradeNameSpaceless, edid: string;
		hqManager, script, curRef, otherMisc: IInterface;
        i: integer;
	begin
        for i:=0 to ReferencedByCount(roomUpgradeMisc)-1 do begin
            curRef := ReferencedByIndex(roomUpgradeMisc, i);

            script := getScript(curRef, 'SimSettlementsV2:HQ:Library:ObjectRefs:HQWorkshopItemActionTrigger');
            if (assigned(script)) then begin
                otherMisc := getScriptProp(script, 'HQAction');
                if(equals(otherMisc, roomUpgradeMisc)) then begin
                    Result := curRef;
                    exit;
                end;
            end;
        end;

        Result := nil;
	end;


    function indexOfElement(list: TStringList; elem: IInterface): integer;
    var
        i: integer;
        curElem: IInterface;
    begin
        Result := -1;
        for i:=0 to list.count-1 do begin
            if(list.Objects[i] <> nil) then begin
                curElem := ObjectToElement(list.Objects[i]);
                if(equals(curElem, elem)) then begin
                    Result := i;
                    exit;
                end;
            end;
        end;
    end;

    function getLayoutDescriptionMsg(existingElem: IInterface; msg, upgradeNameSpaceless, slotNameSpaceless: string): IInterface;
    var
        edidBase, edid: string;
    begin
        if (msg = '') then begin
            exit;
        end;
        if(not assigned(existingElem)) then begin
            edidBase := upgradeNameSpaceless;
            if(slotNameSpaceless <> '') then begin
                edidBase := upgradeNameSpaceless+'_'+slotNameSpaceless;

            end;
            edid := generateEdid('LayoutDescription_', edidBase);
            // 3. A design description field, this should be used to create a Message form and plugged into the InformationMessage property of the layouts.
            //SS2_Name_Dog
            //function getCopyOfTemplateOA(targetFile, template: IInterface; newEdid: string): IInterface;
            //Result := getCopyOfTemplateOA(targetFile, LayoutDescriptionTemplate, edid);
            Result := getElemByEdidAndSig(edid, 'MESG', targetFile);
        end else begin
            Result := getOrCreateElementOverride(existingElem, targetFile);
        end;

        setElementEditValues(Result, 'DESC', msg);
    end;

    function getLayoutNameMisc(existingElem: IInterface; designerName: string): IInterface;
    var
        edid, prevName: string;
    begin
        if (assigned(existingElem)) then begin
            edid := generateEdid('NameHolder_Designer_', '');
            if(EditorID(existingElem) = edid) then begin
                AddMessage('WARNING: found broken name holder. Try deleting it manually: '+FullPath(existingElem));
                existingElem := nil;
            end;
        end;
        if (designerName = '') then begin
            exit;
        end;
        {Field for the designer's name. For this we'll need to create a MiscObject named that, and plug that into the DesignerNameHolder property on each of the layouts.
        Probably should come up with a standard name scheme so you can search it up by EDID and avoid creating duplicates.
        So something like SS2C2_NameHolder_Designer_<alphanumeric characters from the designer's name field>.}

        if(assigned(existingElem)) then begin
            // if the name doesn't mach, create a new one
            prevName := getElementEditValues(existingElem, 'FULL');
            if(LowerCase(trim(prevName)) <> LowerCase(trim(designerName))) then begin
                existingElem := nil;
            end;
        end;

        if(not assigned(existingElem)) then begin
            edid := generateEdid('NameHolder_Designer_', cleanStringForEditorID(designerName));
            Result := getElemByEdidAndSig(edid, 'MISC', targetFile);
        end else begin
            Result := getOrCreateElementOverride(existingElem, targetFile);
        end;

        setElementEditValues(Result, 'FULL', designerName);
    end;

	function createRoomUpgradeMisc(
		existingElem: IInterface;
		targetRoomConfig: IInterface;
		upgradeName: string;
		modelStr: string;
		upgradeSlot: IInterface;
		assignAtStart: boolean;
		assignAtEnd: boolean;
		defaultMarkers: boolean;
		disableClutter: boolean;
		disableGarbage: boolean;
		realTime: boolean;
		duration: float;
		targetDepartment: IInterface;
		resources: TStringList;
		roomFuncs: TStringList;
		layouts: TStringList;
		actionGroup: IInterface;
        roomMode: integer;
        slotLists: TStringList;
        designerName, designDescription: string
    ): IInterface;
	var
		upgradeResult: IInterface;
		upgradeNameSpaceless, slotNameSpaceless, upgradeEdid, upgradeEdidPart, ActionAvailableGlobalEdid, HqName: string;
		script, roomCfgScript, ActionAvailableGlobal: IInterface;
		i, resIndex, resCount: integer;
		ResourceCost, ProvidedFunctionality, RoomLayouts, curResObject, curRoomFunc, newStruct, RoomRequiredKeywords, UpgradeSlotKeyword: IInterface;
		resourceJson: TJsonObject;
		curLayout: IInterface;
		curLayoutName, curLayoutPath, selectedSlotStr, curSlotName, kwBase, roomShapePart: string;
		upgradeSlotLayout, roomShapeKeyword, upgradeSlotKw, oldUpgradeSlotKw, oldUpgradeSlot, AdditionalUpgradeSlots, curSlot, curSlotMisc: IInterface;
        descriptionMsg, designerMisc: IInterface;
        designerData: TJsonObject;
	begin

		HqName := findHqNameShort(targetHq);
		slotNameSpaceless := cleanStringForEditorID(getElementEditValues(upgradeSlot, 'FULL'));

		upgradeNameSpaceless := cleanStringForEditorID(upgradeName);
        roomShapeKeyword := getRoomShapeKeywordFromConfig(targetRoomConfig);
        roomShapePart := getRoomShapeUniquePart(EditorID(roomShapeKeyword));

        if(not assigned(existingElem)) then begin
            if(roomMode = 0) then begin
                upgradeEdidPart := '_Action_RoomConstruction_';
            end else begin
                upgradeEdidPart := '_Action_RoomUpgrade_';
            end;
            upgradeEdidPart := upgradeEdidPart+roomShapePart+'_';

            upgradeEdid := generateEdid('HQ'+HqName, upgradeEdidPart + upgradeNameSpaceless);
            upgradeResult := getCopyOfTemplateOA(targetFile, SS2_HQ_Action_RoomUpgrade_Template, upgradeEdid);
        end else begin
            upgradeResult := getOrCreateElementOverride(existingElem, targetFile);
        end;

        // upgrade or construction?
        // roomMode is:
        // 0 = construction
        // 1 = upgrade

        // removeKeywordByPath
        {SS2_Tag_HQ_ActionType_RoomConstruction
        SS2_Tag_HQ_ActionType_RoomUpgrade}
        if(roomMode = 0) then begin
            removeKeywordByPath(upgradeResult, SS2_Tag_HQ_ActionType_RoomUpgrade, 'KWDA');
            ensureKeywordByPath(upgradeResult, SS2_Tag_HQ_ActionType_RoomConstruction, 'KWDA');
        end else begin
            removeKeywordByPath(upgradeResult, SS2_Tag_HQ_ActionType_RoomConstruction, 'KWDA');
            ensureKeywordByPath(upgradeResult, SS2_Tag_HQ_ActionType_RoomUpgrade, 'KWDA');
        end;

		if(modelStr <> '') then begin
			ensurePath(upgradeResult, 'Model\MODL');
			SetElementEditValues(upgradeResult, 'Model\MODL', modelStr);
		end;

		setPathLinksTo(upgradeResult, 'PTRN', SS2_TF_HologramGNNWorkshopTiny);

		SetElementEditValues(upgradeResult, 'FULL', upgradeName);

		script := getScript(upgradeResult, 'SimSettlementsV2:HQ:BaseActionTypes:HQRoomUpgrade');

		setScriptProp(script, 'bAssignDepartmentToRoomAtStartOfAction', assignAtStart);
		setScriptProp(script, 'bAssignDepartmentToRoomAtEndOfAction', assignAtEnd);
		setScriptProp(script, 'bDisableClutter_OnCompletion', disableClutter);
		setScriptProp(script, 'bDisableGarbage_OnCompletion', disableGarbage);
		setScriptProp(script, 'bUseDefaultConstructionMarkers', defaultMarkers);
		setScriptProp(script, 'RealTimeTimer', realTime);
        // autofixing old fail
		deleteScriptProp(script, 'bDisableGarbage_OnComplete');

		setScriptProp(script, 'Duration', duration);

		roomCfgScript := getScript(targetRoomConfig, 'SimSettlementsV2:HQ:Library:MiscObjects:RequirementTypes:ActionTypes:HQRoomConfig');
		//actionGroup := getScriptProp(roomCfgScript, 'ActionGroup');

		setScriptProp(script, 'DepartmentHQActionGroup', actionGroup);


		UpgradeSlotKeyword := getScriptProp(roomCfgScript, 'RoomShapeKeyword');
		RoomRequiredKeywords := getScriptProp(script, 'RoomRequiredKeywords');

        if (assigned(existingElem)) then begin
            clearProperty(RoomRequiredKeywords);
            appendObjectToProperty(RoomRequiredKeywords, SS2_Tag_HQ_RoomIsClean);
            //clearRoomRequiredKeywordsExcept(RoomRequiredKeywords, 'SS2_Tag_HQ_RoomIsClean');
        end;
		appendObjectToProperty(RoomRequiredKeywords, UpgradeSlotKeyword);



		if(assigned(targetDepartment)) then begin
			setScriptProp(script, 'NewDepartmentOnCompletion', targetDepartment);
		end else begin
            if (assigned(existingElem)) then begin
                clearScriptProp(script, 'NewDepartmentOnCompletion');
            end;
        end;

        ActionAvailableGlobalEdid := generateEdid('HQActionAvailable_'+HqName+'_', roomShapePart+'_gl_'+upgradeNameSpaceless);
        ActionAvailableGlobal := nil;

        if(assigned(existingElem)) then begin
            ActionAvailableGlobal := getScriptProp(script, 'ActionAvailableGlobal');
        end;


        if(not assigned(ActionAvailableGlobal)) then begin
            // make ActionAvailableGlobal
            // if updating, assume this exists already
            //ActionAvailableGlobalEdid := generateEdid('HQActionAvailable_'+HqName+'_', upgradeNameSpaceless);
            ActionAvailableGlobal := getCopyOfTemplateOA(targetFile, versionGlobalTemplate, ActionAvailableGlobalEdid);
            // how do I remove the CONST flag?
            SetElementEditValues(ActionAvailableGlobal, 'Record Header\Record Flags\Constant', '0');
            SetElementEditValues(ActionAvailableGlobal, 'FLTV', '0');

            setScriptProp(script, 'ActionAvailableGlobal', ActionAvailableGlobal);
        end;


        ensureKeywordByPath(upgradeResult, roomShapeKeyword, 'KWDA');

        oldUpgradeSlot := getScriptProp(script, 'TargetUpgradeSlot');
        if(assigned(oldUpgradeSlot)) then begin
            // upgradeSlotKw, oldUpgradeSlotKw, oldUpgradeSlot
            oldUpgradeSlotKw := findSlotKeywordFromSlotMisc(oldUpgradeSlot);
            removeKeywordByPath(upgradeResult, oldUpgradeSlotKw, 'KWDA');
        end;

        upgradeSlotKw := findSlotKeywordFromSlotMisc(upgradeSlot);

        ensureKeywordByPath(upgradeResult, upgradeSlotKw, 'KWDA');
        // put upgradeSlot onto the misc
        // for existing, read TargetUpgradeSlot, remove it from misc

		setScriptProp(script, 'TargetUpgradeSlot', upgradeSlot);


		// prop: ResourceCost -> array of struct HQTransactionItem
		ResourceCost := getOrCreateScriptPropArrayOfStruct(script, 'ResourceCost');

        // clear the property if we're updating
        if(assigned(existingElem)) then begin
            clearProperty(ResourceCost);
        end;

		for i:=0 to resources.count-1 do begin
			resourceJson := TJsonObject(resources.Objects[i]);

			resIndex := resourceJson.I['index'];
			resCount := resourceJson.I['count'];

			curResObject := ObjectToElement(listRoomResources.Objects[resIndex]);

			newStruct := appendStructToProperty(ResourceCost);

			setStructMember(newStruct, 'Item', curResObject);
			setStructMember(newStruct, 'iCount', resCount);
		end;

        if(roomFuncs.count > 0) then begin
            ProvidedFunctionality := getOrCreateScriptPropArrayOfObject(script, 'ProvidedFunctionality');
            // clear the property if we're updating
            if(assigned(existingElem)) then begin
                clearProperty(ProvidedFunctionality);
            end;

            for i:=0 to roomFuncs.count-1 do begin
                curRoomFunc := ObjectToElement(roomFuncs.Objects[i]);
                appendObjectToProperty(ProvidedFunctionality, curRoomFunc);
            end;
		end else begin
            // delete it if it exists
            if(assigned(existingElem)) then begin
                deleteScriptProp(script, 'ProvidedFunctionality');
            end;
        end;

		hasRelativeCoordinateLayout   := false;
		hasNonRelativeCoordinateLayout:= false;

        // slotLists
        if(slotLists.count > 0) then begin

            AdditionalUpgradeSlots := getOrCreateScriptPropArrayOfObject(script, 'AdditionalUpgradeSlots');
            if(assigned(existingElem)) then begin
                clearProperty(AdditionalUpgradeSlots);
            end;

            kwBase := getRoomShapeUniquePart(EditorID(roomShapeKeyword));
            for i:=0 to slotLists.count-1 do begin
                // curSlot := getObjectFromProperty(AdditionalUpgradeSlots, i);
                curSlot := ObjectToElement(slotLists.Objects[i]);
                curSlotName := slotLists[i];

                curSlotMisc := getUpgradeSlot(curSlot, kwBase, upgradeNameSpaceless, curSlotName, targetHQ);

                appendObjectToProperty(AdditionalUpgradeSlots, curSlotMisc);
            end;
        end else begin
            if(assigned(existingElem)) then begin
                deleteScriptProp(script, 'AdditionalUpgradeSlots');
            end;
        end;

        if(layouts.count > 0) then begin
            // find
            designerData := getDesignerObjectsFromUpgradeScript(script);

            descriptionMsg  := nil;
            designerMisc    := nil;

            if(designerData <> nil) then begin
                descriptionMsg  := AbsStrToForm(designerData.S['desc']);
                designerMisc    := AbsStrToForm(designerData.S['name']);
                designerData.free();
            end;

            descriptionMsg := getLayoutDescriptionMsg(descriptionMsg, designDescription, upgradeNameSpaceless, slotNameSpaceless);
            designerMisc   := getLayoutNameMisc(designerMisc, designerName);

            RoomLayouts := getOrCreateScriptPropArrayOfObject(script, 'RoomLayouts');
            if(assigned(existingElem)) then begin
                updateExistingLayouts(targetHq, RoomLayouts, targetRoomConfig, layouts, upgradeNameSpaceless, slotNameSpaceless, descriptionMsg, designerMisc);

            end else begin
                // create layouts from scratch
                for i:=0 to layouts.count-1 do begin
                    resourceJson := TJsonObject(layouts.Objects[i]);

                    curLayoutName := resourceJson.S['name'];
                    curLayoutPath := resourceJson.S['path'];
                    selectedSlotStr := resourceJson.S['slot'];
                    upgradeSlotLayout := AbsStrToForm(selectedSlotStr);

                    curLayout := createRoomLayout(nil, targetHq, targetRoomConfig, curLayoutName, curLayoutPath, upgradeNameSpaceless, slotNameSpaceless, upgradeSlotLayout, descriptionMsg, designerMisc);

                    appendObjectToProperty(RoomLayouts, curLayout);
                end;

                if(hasRelativeCoordinateLayout and hasNonRelativeCoordinateLayout) then begin
                    AddMessage('=== WARNING: some but not all layouts have a RoomExportHelper. This is probably a mistake, they should either all have it, or none should.');
                end;
            end;
        end else begin
            // delete it if it exists
            if(assigned(existingElem)) then begin
                RoomLayouts := getScriptProp(script, 'RoomLayouts');
                for i:=0 to ElementCount(RoomLayouts)-1 do begin
                    recycleLayout(ElementByIndex(RoomLayouts, i), i);
                end;
                deleteScriptProp(script, 'RoomLayouts');
            end;
		end;

		Result := upgradeResult;
	end;

    function createTechResearchMisc(
		existingElem: IInterface;
		// targetRoomConfig: IInterface;
		upgradeName: string;
        modelStr: string;
		completable: boolean;
		realTime: boolean;
		duration: float;
        resources: TStringList;
		miscTemplate: IInterface
    ): IInterface;
	var
		upgradeResult: IInterface;
		upgradeNameSpaceless, slotNameSpaceless, upgradeEdid, upgradeEdidPart, ActionAvailableGlobalEdid, HqName: string;
		script, roomCfgScript, ActionAvailableGlobal: IInterface;
		i, resIndex, resCount: integer;
		ResourceCost, ProvidedFunctionality, RoomLayouts, curResObject, curRoomFunc, newStruct, RoomRequiredKeywords, UpgradeSlotKeyword: IInterface;
		resourceJson: TJsonObject;
		curLayout: IInterface;
		curLayoutName, curLayoutPath, selectedSlotStr, curSlotName, kwBase, roomShapePart: string;
		upgradeSlotLayout, roomShapeKeyword, upgradeSlotKw, oldUpgradeSlotKw, oldUpgradeSlot, AdditionalUpgradeSlots, curSlot, curSlotMisc: IInterface;
        descriptionMsg, designerMisc: IInterface;
        designerData: TJsonObject;
	begin

		HqName := findHqNameShort(targetHq);
		//slotNameSpaceless := cleanStringForEditorID(getElementEditValues(upgradeSlot, 'FULL'));

		upgradeNameSpaceless := cleanStringForEditorID(upgradeName);
        // roomShapeKeyword := getRoomShapeKeywordFromConfig(targetRoomConfig);
        // roomShapePart := getRoomShapeUniquePart(EditorID(roomShapeKeyword));

        if(not assigned(existingElem)) then begin
            upgradeEdidPart := '_Action_TechResearch_';

            upgradeEdid := generateEdid('HQ'+HqName, upgradeEdidPart + upgradeNameSpaceless); //configMiscEdid := 'SS2_HQ' + findHqNameShort(forHq)+'_Action_AssignRoomConfig_'+kwBase+'_'+roomNameSpaceless;
            upgradeResult := getCopyOfTemplateOA(targetFile, miscTemplate, upgradeEdid);
        end else begin
            upgradeResult := getOrCreateElementOverride(existingElem, targetFile);
        end;

        if(modelStr <> '') then begin
			ensurePath(upgradeResult, 'Model\MODL');
			SetElementEditValues(upgradeResult, 'Model\MODL', modelStr);
		end;

        // we don't have:
        //  upgradeSlot, targetDepartment, roomFuncs, layouts, slotLists
        // also disregard
        //  assignAtStart, assignAtEnd, defaultMarkers, disableClutter, disableGarbage


        // maybe?
        {
        removeKeywordByPath(upgradeResult, SS2_Tag_HQ_ActionType_RoomUpgrade, 'KWDA');
        removeKeywordByPath(upgradeResult, SS2_Tag_HQ_ActionType_RoomConstruction, 'KWDA');
        // TODO try to remove the wrong KWs from the thing in the other function?
        }
        //ensureKeywordByPath(upgradeResult, SS2_Tag_HQ_ActionType_RoomUpgrade, 'KWDA');

		setPathLinksTo(upgradeResult, 'PTRN', SS2_TF_HologramGNNWorkshopTiny);

		SetElementEditValues(upgradeResult, 'FULL', upgradeName);

		script := getFirstScript(upgradeResult);

        {
        maybe cleanup?
		setScriptProp(script, 'bAssignDepartmentToRoomAtStartOfAction', assignAtStart);
		setScriptProp(script, 'bAssignDepartmentToRoomAtEndOfAction', assignAtEnd);
		setScriptProp(script, 'bDisableClutter_OnCompletion', disableClutter);
		setScriptProp(script, 'bDisableGarbage_OnCompletion', disableGarbage);
		setScriptProp(script, 'bUseDefaultConstructionMarkers', defaultMarkers);
        }
		setScriptProp(script, 'RealTimeTimer', realTime);
		setScriptProp(script, 'Completable', completable);

		setScriptProp(script, 'Duration', duration);


//		setScriptProp(script, 'DepartmentHQActionGroup', actionGroup);


        {
		roomCfgScript := getScript(targetRoomConfig, 'SimSettlementsV2:HQ:Library:MiscObjects:RequirementTypes:ActionTypes:HQRoomConfig');
		//UpgradeSlotKeyword := getScriptProp(roomCfgScript, 'RoomShapeKeyword');
		RoomRequiredKeywords := getScriptProp(script, 'RoomRequiredKeywords');

        if (assigned(existingElem)) then begin
            clearProperty(RoomRequiredKeywords);
            appendObjectToProperty(RoomRequiredKeywords, SS2_Tag_HQ_RoomIsClean);
            //clearRoomRequiredKeywordsExcept(RoomRequiredKeywords, 'SS2_Tag_HQ_RoomIsClean');
        end;
        }
		//appendObjectToProperty(RoomRequiredKeywords, UpgradeSlotKeyword);


        {
		if(assigned(targetDepartment)) then begin
			setScriptProp(script, 'NewDepartmentOnCompletion', targetDepartment);
		end else begin
            if (assigned(existingElem)) then begin
                clearScriptProp(script, 'NewDepartmentOnCompletion');
            end;
        end;
        }

        ActionAvailableGlobalEdid := generateEdid('HQActionAvailable_'+HqName+'_', upgradeNameSpaceless);
        ActionAvailableGlobal := nil;

        if(assigned(existingElem)) then begin
            ActionAvailableGlobal := getScriptProp(script, 'ActionAvailableGlobal');
        end;

        if(not assigned(ActionAvailableGlobal)) then begin
            // make ActionAvailableGlobal
            ActionAvailableGlobal := getCopyOfTemplateOA(targetFile, versionGlobalTemplate, ActionAvailableGlobalEdid);
            // how do I remove the CONST flag?
            SetElementEditValues(ActionAvailableGlobal, 'Record Header\Record Flags\Constant', '0');
            SetElementEditValues(ActionAvailableGlobal, 'FLTV', '0');

            setScriptProp(script, 'ActionAvailableGlobal', ActionAvailableGlobal);
        end;


        //upgradeSlotKw := findSlotKeywordFromSlotMisc(upgradeSlot);

        //ensureKeywordByPath(upgradeResult, upgradeSlotKw, 'KWDA');
        // put upgradeSlot onto the misc
        // for existing, read TargetUpgradeSlot, remove it from misc

		//setScriptProp(script, 'TargetUpgradeSlot', upgradeSlot);


		// prop: ResourceCost -> array of struct HQTransactionItem
		ResourceCost := getOrCreateScriptPropArrayOfStruct(script, 'ResourceCost');

        // clear the property if we're updating
        if(assigned(existingElem)) then begin
            clearProperty(ResourceCost);
        end;

		for i:=0 to resources.count-1 do begin
			resourceJson := TJsonObject(resources.Objects[i]);

			resIndex := resourceJson.I['index'];
			resCount := resourceJson.I['count'];

			curResObject := ObjectToElement(listRoomResources.Objects[resIndex]);

			newStruct := appendStructToProperty(ResourceCost);

			setStructMember(newStruct, 'Item', curResObject);
			setStructMember(newStruct, 'iCount', resCount);
		end;

		Result := upgradeResult;
	end;

    procedure recycleLayout(layout: IInterface; i: integer);
    begin
        AddMessage('RECYCLING '+EditorID(layout));
        deleteScriptProps(layout);
        SetElementEditValues(layout, 'FULL', 'Deleted Layout #'+IntToStr(i));
    end;

    procedure removeExistingLayouts(layouts: TStringList);
    var
        i: integer;
        curLayout: IInterface;
    begin
        // at least remove the data from the leftovers, if we have them
        for i:=0 to layouts.count-1 do begin
            curLayout := ObjectToElement(layouts.Objects[i]);
            recycleLayout(curLayout, i);
        end;
    end;

    procedure updateExistingLayouts(targetHq, RoomLayouts, roomConfig: IInterface; layouts: TStringList; upgradeNameSpaceless, slotNameSpaceless: string; descriptionMsg, designerMisc: IInterface);
    var
        prevLayouts, recycleLayouts, usedLayouts, newLayouts: TStringList;
        i: integer;
        curLayout, newLayout, upgradeSlotLayout: IInterface;
        edid, layoutStr: string;
        curJsonData: TJsonObject;
    begin
        prevLayouts := TStringList.create;
        recycleLayouts := TStringList.create;
        usedLayouts := TStringList.create;
        newLayouts := TStringList.create;

        // get all the layouts we have
        for i:=0 to ElementCount(RoomLayouts)-1 do begin
            curLayout := getObjectFromProperty(RoomLayouts, i);
            edid := EditorID(curLayout);

            AddMessage('Preexisting layout: '+edid);
            prevLayouts.addObject(edid, curLayout);
        end;

        // find which layouts we must not recycle
        for i:=0 to layouts.count-1 do begin
            curJsonData := layouts.Objects[i];
            curLayout := nil;
            layoutStr := curJsonData.S['existing'];
            if(layoutStr <> '') then begin
                curLayout := AbsStrToForm(layoutStr);
            end;

            if(assigned(curLayout)) then begin
                edid := EditorID(curLayout);
                AddMessage('Layout still in use: '+edid);
                usedLayouts.addObject(edid, curLayout);
            end;
        end;

        // now which are recycleable
        for i:=0 to prevLayouts.count-1 do begin
            edid := prevLayouts[i];
            curLayout := ObjectToElement(prevLayouts.Objects[i]);

            if(usedLayouts.indexOf(edid) < 0) then begin
                // unused
                AddMessage('Layout for recycling: '+edid);
                recycleLayouts.addObject(edid, curLayout);
            end;
        end;

        // now do the things
        for i:=0 to layouts.count-1 do begin
            curJsonData := layouts.Objects[i];

            curLayout := nil;
            layoutStr := curJsonData.S['existing'];
            if(layoutStr <> '') then begin
                curLayout := AbsStrToForm(layoutStr);
            end;

            upgradeSlotLayout := AbsStrToForm(curJsonData.S['slot']);

            if(assigned(curLayout)) then begin
                // updating
                AddMessage('Updating '+EditorID(curLayout));
                newLayout := createRoomLayout(curLayout, targetHq, roomConfig, curJsonData.S['name'], curJsonData.S['path'], upgradeNameSpaceless, slotNameSpaceless, upgradeSlotLayout, descriptionMsg, designerMisc);

                newLayouts.addObject(EditorID(newLayout), newLayout);
            end else begin
                // creating new
                // do we have some to recycle?
                if(recycleLayouts.count > 0) then begin
                    curLayout := ObjectToElement(recycleLayouts.Objects[0]);
                    recycleLayouts.delete(0);
                end;
                if(curJsonData.S['path'] <> '') then begin
                    //AddMessage('Generating layout. Using recycled? '+BoolToStr(curLayout));
                    newLayout := createRoomLayout(curLayout, targetHq, roomConfig, curJsonData.S['name'], curJsonData.S['path'], upgradeNameSpaceless, slotNameSpaceless, upgradeSlotLayout, descriptionMsg, designerMisc);
                    newLayouts.addObject(EditorID(newLayout), newLayout);
                end;
            end;
        end;

        // at this point, we are ready to write
        clearProperty(RoomLayouts);

        for i:=0 to newLayouts.count-1 do begin
            curLayout := ObjectToElement(newLayouts.Objects[i]);
            appendObjectToProperty(RoomLayouts, curLayout);
        end;

        // at least remove the data from the leftovers, if we have them
        removeExistingLayouts(recycleLayouts);

        prevLayouts.free();
        recycleLayouts.free();
        usedLayouts.free();
        newLayouts.free();
    end;

	function getActionAvailableGlobal(upgradeMisc: IInterface): IInterface;
	var
		script: IInterface;
	begin
        //SimSettlementsV2:HQ:Library:MiscObjects:RequirementTypes:HQAction
        //SimSettlementsV2:HQ:BaseActionTypes:HQRoomUpgrade
		// script := getScript(upgradeMisc, 'SimSettlementsV2:HQ:BaseActionTypes:HQRoomUpgrade');
		//script := findScriptInElementByName(upgradeMisc, 'SimSettlementsV2:HQ:Library:MiscObjects:RequirementTypes:HQAction');
		script := getFirstScript(upgradeMisc);
		Result := getScriptProp(script, 'ActionAvailableGlobal');
	end;



    function selectRoomConfig(caption: string): IInterface;
	var
        frm: TForm;
		btnOk, btnCancel: TButton;
		resultCode, curY: integer;
		selectRoomConfig: TComboBox;
	begin
        Result := nil;

		frm := CreateDialog(caption, 540, 180);
		frm.Name := 'roomUpgradeDialog1';
		curY := 0;

		// targetHQ
		CreateLabel(frm, 10, 10+curY, 'HQ: '+EditorID(targetHQ)+'.');
		CreateLabel(frm, 10, 38+curY, 'Select Room Config to continue:');

		curY := curY + 44;
		selectRoomConfig := CreateComboBox(frm, 10, 8+curY, 500, listRoomConfigs);
		selectRoomConfig.Style := csDropDownList;
		selectRoomConfig.Name := 'selectRoomConfig';
		selectRoomConfig.onChange := updateRoomUpgrade1OkBtn;

		curY := curY + 64;
		btnOk := CreateButton(frm, 200, curY, 'OK');
		btnOk.ModalResult := mrYes;
		btnOk.Name := 'btnOk';
		btnOk.Default := true;

		btnCancel := CreateButton(frm, 275	, curY, 'Cancel');
		btnCancel.ModalResult := mrCancel;

		btnOk.Width := 75;
		btnCancel.Width := 75;

		updateRoomUpgrade1OkBtn(btnOk);

		resultCode := frm.ShowModal();

		if(resultCode = mrYes) then begin
			Result := ObjectToElement(listRoomConfigs.Objects[selectRoomConfig.ItemIndex]);
		end;
		frm.free();
	end;

	procedure showRoomUpgradeDialog(existingElem: IInterface);
	var
		selectedRoomConfig: IInterface;
        windowCaption: string;
	begin
        windowCaption := 'Generating Room Upgrade';
        if(assigned(existingElem)) then begin
            selectedRoomConfig := findRoomConfigFromRoomUpgrade(existingElem);
            if(assigned(selectedRoomConfig)) then begin
                // we can contine from here
                showRoomUpgradeDialog2(selectedRoomConfig, existingElem);
                exit;
            end;
            windowCaption := 'Updating Room Upgrade';
        end;

        selectedRoomConfig := selectRoomConfig(windowCaption);

		if(assigned(selectedRoomConfig)) then begin
			showRoomUpgradeDialog2(selectedRoomConfig, existingElem);
		end;
	end;

    function findEditorIdPrefix(existingElem: IInterface): string;
    var
        edid: string;
        underscorePos: integer;
    begin
        Result := '';

        if(not assigned(existingElem)) then begin
            exit;
        end;

        edid := EditorID(existingElem);

        underscorePos := pos('_', edid);
        if(underscorePos < 1) then begin
            exit;
        end;

        Result := copy(edid, 0, underscorePos);

    end;

	procedure showRoomConfigDialog(existingElem: IInterface);
	var
        frm: TForm;
		selectRoomShape, selectMainDep, selectActionGroup: TComboBox;
		curY, resultCode, secondRowOffset: integer;
		inputName, inputPrefix: TEdit;
		listSlots: TListBox;
		btnAddSlot, btnRemSlot, btnOk, btnCancel: TButton;

		roomName: string;
		roomShapeKw: IInterface;
		roomShapeKwEdid: string;
		actionGroup: IInterface;
		primaryDepartment: IInterface;

		doRegisterCb: TCheckBox;

		createdConfig: IInterface;
		existingRoomshape, existingActionGroup, existingPrimaryDepartment, configMiscScript: IInterface;
		i: integer;
		existingSlotProps, curExistingSlot: IInterface;
		existingSlotName: string;
        departmentList: TStringList;
	begin
        //if (trim(inputName.text) <> '') and (trim(inputPrefix.text) <> '') and (selectActionGroup.ItemIndex >= 0) and ((selectRoomShape.ItemIndex >= 0) or (trim(selectRoomShape.text) <> '')) then begin
		curY := 0;
		frm := CreateDialog('Room Config', 570, 348);
		frm.Name := 'roomConfigDialog';

		CreateLabel(frm, 10, 10, 'Target HQ: '+findHqName(targetHQ));

		curY := 24;
		secondRowOffset := 300;

		CreateLabel(frm, 10, 10+curY, 'Room Name:*');
		inputName := CreateInput(frm, 120, 8+curY, '');
		inputName.width := 200;
		inputName.Name := 'inputName';
		inputName.Text := '';
		inputName.onChange := updateRoomConfigOkBtn;

		CreateLabel(frm, secondRowOffset+30, 10+curY, 'EditorID Prefix:*');
		inputPrefix := CreateInput(frm, secondRowOffset+120, 8+curY, '');
		inputPrefix.Name := 'inputPrefix';
		inputPrefix.Text := '';
		inputPrefix.width := 130;
		inputPrefix.onChange := updateRoomConfigOkBtn;



		curY := curY + 24;
		CreateLabel(frm, 10, 10+curY, 'Room Shape:*');

		selectRoomShape := CreateComboBox(frm, 120, 8+curY, 430, listRoomShapes);
		selectRoomShape.Name := 'selectRoomShape';
		selectRoomShape.Text := '';
		selectRoomShape.onChange := updateRoomConfigOkBtn;

		curY := curY + 24;
		CreateLabel(frm, 10, 10+curY, 'Action Group:*');
		selectActionGroup := CreateComboBox(frm, 120, 8+curY, 430, listActionGroups);
		selectActionGroup.Style := csDropDownList;
		selectActionGroup.Name := 'selectActionGroup';
		selectActionGroup.onChange := updateRoomConfigOkBtn;

        departmentList := prependDummyEntry( listDepartmentObjects, '- NONE -');

		curY := curY + 24;
		CreateLabel(frm, 10, 10+curY, 'Primary Department:');
		selectMainDep := CreateComboBox(frm, 120, 8+curY, 430, departmentList);
		selectMainDep.Style := csDropDownList;
		selectMainDep.Name := 'selectMainDep';
		// selectMainDep.onChange := updateRoomConfigOkBtn;
		selectMainDep.ItemIndex := 0;

		curY := curY + 24;
		CreateLabel(frm, 10, 12+curY, 'Upgrade Slots:');
		curY := curY + 24;

		//defaultSlotsList := TStringList.create();


		listSlots := CreateListBox(frm, 10, 10+curY, 200, 100, nil);
		listSlots.Name := 'listSlots';

		listSlots.Multiselect := true;
        setupMenu(listSlots);
        listSlots.OnKeyDown := listboxKeyPressHandler;

		listSlots.items.add('Base');
		listSlots.items.add('Decoration');
		listSlots.items.add('Lighting');
		listSlots.items.add('FactionTheming');
		listSlots.items.add('HolidayTheming');

		btnAddSlot := CreateButton(frm, 220, 20+curY, 'Add Slot');
		btnRemSlot := CreateButton(frm, 220, 48+curY, 'Remove Slot');

		btnAddSlot.onClick := addUpgradeSlotHandler;
		btnRemSlot.onClick := remUpgradeSlotHandler;

		btnAddSlot.Width := 100;
		btnRemSlot.Width := 100;

		curY := curY + 118;
		doRegisterCb := CreateCheckbox(frm, 10, curY, 'Register Room Config');
		doRegisterCb.checked := true;

		curY := curY + 24;
		btnOk := CreateButton(frm, 200, curY, 'OK');
		btnOk.ModalResult := mrYes;
		btnOk.Name := 'btnOk';
		btnOk.Default := true;

		btnCancel := CreateButton(frm, 275	, curY, 'Cancel');
		btnCancel.ModalResult := mrCancel;

		btnOk.Width := 75;
		btnCancel.Width := 75;


		// change some stuff, if we are updating
		if(assigned(existingElem)) then begin

            doRegisterCb.checked := false;
            doRegisterCb.enabled := false;

			inputName.Text := GetElementEditValues(existingElem, 'FULL');
			// existing roomshape
			existingRoomshape := findKeywordByList(existingElem, listRoomShapes);
			if(assigned(existingRoomshape)) then begin
				setItemIndexByForm(selectRoomShape, existingRoomshape);
			end;

			configMiscScript := getScript(existingElem, 'SimSettlementsV2:HQ:Library:MiscObjects:RequirementTypes:ActionTypes:HQRoomConfig');
			existingActionGroup := getScriptProp(configMiscScript, 'ActionGroup');
			if(assigned(existingActionGroup)) then begin
				setItemIndexByForm(selectActionGroup, existingActionGroup);
			end;

			existingPrimaryDepartment := getScriptProp(configMiscScript, 'PrimaryDepartment');
			if(assigned(existingPrimaryDepartment)) then begin
				setItemIndexByForm(selectMainDep, existingPrimaryDepartment);
			end;

			// load the slots
			listSlots.items.clear();
			existingSlotProps := getScriptProp(configMiscScript, 'RoomUpgradeSlots');
			for i:=0 to ElementCount(existingSlotProps)-1 do begin
				curExistingSlot := getObjectFromProperty(existingSlotProps, i);
				existingSlotName := GetRoomSlotName(curExistingSlot);
				listSlots.items.addObject(existingSlotName, curExistingSlot);
			end;

            inputPrefix.Text := findEditorIdPrefix(existingElem);
		end;

		updateRoomConfigOkBtn(btnCancel);

		resultCode := frm.ShowModal();
		if(resultCode = mrYes) then begin
			globalNewFormPrefix := trim(inputPrefix.Text);

			// do stuff
			roomName := trim(inputName.Text);
			roomShapeKw := nil;
			roomShapeKwEdid := cleanStringForEditorID(selectRoomShape.Text);
            if(selectMainDep.ItemIndex > 0) then begin
                primaryDepartment := ObjectToElement(departmentList.Objects[selectMainDep.ItemIndex]);
            end else begin
                primaryDepartment := nil;
            end;
			actionGroup := ObjectToElement(listActionGroups.Objects[selectActionGroup.ItemIndex]);

			if(selectRoomShape.ItemIndex >= 0) then begin
				roomShapeKw := ObjectToElement(listRoomShapes.Objects[selectRoomShape.ItemIndex]);
			end;

			createdConfig := createHqRoomConfig(existingElem, targetHQ, roomName, roomShapeKw, roomShapeKwEdid, actionGroup, primaryDepartment, listSlots.items);

			if(doRegisterCb.checked) then begin
				AddMessage('Registering Room Config');
				registerAddonContent(targetFile, createdConfig, SS2_FLID_HQActions);
			end;
			AddMessage('Room Config generated!');
		end;

        departmentList.free();

		frm.free();
	end;

	procedure showMultipleChoiceDialog();
	var
		frm: TForm;
		selectHq: TComboBox;
		btnOk, btnCancel: TButton;
		resultCode, selectedIndex, selectedHQIndex, curY: integer;
		modeRGroup: TRadioGroup;

	begin

		frm := CreateDialog('HQ Room Script', 420, 210);


		curY := 0;
		CreateLabel(frm, 10, curY+10, 'No record selected. What do you want to generate?');
		curY := curY+24;
		CreateLabel(frm, 10, curY+10, 'Target HQ:');



		selectHq := CreateComboBox(frm, 150, curY+8, 250, listHQRefs);
		selectHq.Style := csDropDownList;
		selectHq.ItemIndex := 0;

		curY := curY+24;

		modeRGroup := CreateRadioGroup(frm, 10, curY + 8, 390, 80, 'Object to generate', nil);
		modeRGroup.Items.add('Room Config');
		modeRGroup.Items.add('Room Construction/Upgrade');
		modeRGroup.Items.add('Tech Research/Other Action');
		modeRGroup.ItemIndex := 0;

		curY := curY + 90;

		btnOk := CreateButton(frm, 130, curY+4, 'OK');
		btnOk.ModalResult := mrYes;
		btnOk.Name := 'btnOk';
		btnOk.Default := true;

		btnCancel := CreateButton(frm, 210, curY+4, 'Cancel');
		btnCancel.ModalResult := mrCancel;

		btnOk.Width := 75;
		btnCancel.Width := 75;

		resultCode := frm.ShowModal();
		selectedIndex := modeRGroup.ItemIndex;
		selectedHQIndex := selectHq.ItemIndex;

		frm.free();

		if(resultCode = mrYes) then begin
			targetHQ := ObjectToElement(listHQRefs.Objects[selectedHQIndex]);
			// loadForms();
			loadFormsForHq(targetHQ);
			if(selectedIndex = 0) then begin
				showRoomConfigDialog(nil);
            end else if (selectedIndex = 1) then begin
                loadForRoomUpgade();
				showRoomUpgradeDialog(nil);
			end else begin
				loadForRoomUpgade();
				showTechResearchDialog(nil);
			end;
		end;

	end;

	function getHqFromRoomActionGroup(actGrp, actGrpScript: IInterface): IInterface;
	var
		curHq: IInterface;
	begin
		if(not assigned(actGrpScript)) then begin
			actGrpScript := findScriptInElementByNameCached(actGrp, 'SimSettlementsV2:HQ:Library:MiscObjects:HQActionGroup');
		end;

		curHq := getScriptProp(actGrpScript, 'HQRef');
		if(not assigned(curHq)) then begin
			Result := SS2_HQ_WorkshopRef_GNN;
			exit;
		end;

		Result := curHq;
	end;

	function getHqFromRoomConfig(configScript: IInterface): IInterface;
	var
		actGrp, actGrpScript, curHq: IInterface;
	begin
		actGrp := getScriptProp(configScript, 'ActionGroup');

		Result := getHqFromRoomActionGroup(actGrp, nil);
	end;

    function getHqFromRoomUpdate(configScript: IInterface): IInterface;
	var
		actGrp, actGrpScript, curHq: IInterface;
	begin
		actGrp := getScriptProp(configScript, 'DepartmentHQActionGroup');

		Result := getHqFromRoomActionGroup(actGrp, nil);
	end;

    function getHqFromLayout(layoutScr: IInterface): IInterface;
    var
        script: IInterface;
    begin
        script := getScript(layout, 'SimSettlementsV2:HQ:Library:Weapons:HQRoomLayout');
        Result := getUniversalForm(script, 'workshopRef');
    end;

    procedure showLayoutUpgradeDialog(layer: IInterface);
    var
        script, targetHQ, slotKeyword: IInterface;
        frm: TForm;
		btnOk, btnCancel, btnBrowse: TButton;
		inputName, inputPath: TEdit;
		title, layoutName, layoutPath, layoutDisplayName, selectedSlotStr, csvPath: string;
		resultCode: integer;
		layoutData: TJsonObject;
		yOffset: integer;
		selectUpgradeSlot: TComboBox;
		roomSlotsOptional: TStringList;
		selectedSlot: IInterface;
        oldFormLabel: TLabel;
        targetRoomConfig, slotMisc: IInterface;
    begin
        script := getScript(layer, 'SimSettlementsV2:HQ:Library:Weapons:HQRoomLayout');

        targetRoomConfig := findRoomConfigFromLayout(layer);
        targetHQ := getUniversalForm(script, 'workshopRef');
        currentListOfUpgradeSlots := getRoomUpgradeSlots(targetHq, targetRoomConfig);

        slotMisc := findSlotMiscFromLayout(layer);

        layoutName := getElementEditValues(layer, 'FULL');

		frm := CreateDialog('Edit Room Layout', 400, 190);

		yOffset := 0;

		oldFormLabel := CreateLabel(frm, 10, yOffset+10, 'Layout Name:');
        oldFormLabel.Name := 'oldFormLabel';
		inputName := CreateInput(frm, 150, yOffset+8, '');
		inputName.Name := 'inputName';
		inputName.Text := layoutName;
		inputName.onchange := layoutBrowseUpdateOk;
		inputName.Width := 150;

		// TODO: add a "custom" entry or such, which would generate a new KW from scratch
		//roomSlotsOptional := prependDummyEntry(currentListOfUpgradeSlots, '- DEFAULT -');
		// TODO: limit the list by which are filled already
		roomSlotsOptional := currentListOfUpgradeSlots;

		yOffset := yOffset + 24;
		CreateLabel(frm, 10, yOffset+10, 'Upgrade Slot:');
		selectUpgradeSlot := CreateComboBox(frm, 150, yOffset+8, 150, roomSlotsOptional);
		selectUpgradeSlot.Style := csDropDownList;
		selectUpgradeSlot.Name := 'selectUpgradeSlot';
		selectUpgradeSlot.ItemIndex := 0;

        setItemIndexByForm(selectUpgradeSlot, slotMisc);

		yOffset := yOffset + 24;

        oldFormLabel := CreateLabel(frm, 10, yOffset+10, '');

		yOffset := yOffset + 32;
		CreateLabel(frm, 10, yOffset, 'Layout Spawns File:');
		inputPath := CreateInput(frm, 10, 20+yOffset, '');
		inputPath.Width := 320;
		inputPath.Name := 'inputPath';
		inputPath.Text := '';
		inputPath.onchange := layoutBrowseUpdateOk;

		btnBrowse := CreateButton(frm, 340, 18+yOffset, '...');
		btnBrowse.onclick := layoutBrowseHandler;

		yOffset := yOffset + 48;
		btnOk := CreateButton(frm, 100, yOffset, 'OK');
		btnOk.ModalResult := mrYes;
		btnOk.Name := 'btnOk';
		btnOk.Default := true;

		btnCancel := CreateButton(frm, 200, yOffset, 'Cancel');
		btnCancel.ModalResult := mrCancel;

		btnOk.Width := 75;
		btnCancel.Width := 75;

        resultCode := frm.showModal();
        if(resultCode = mrYes) then begin
            csvPath := trim(inputPath.Text);
            layoutName := trim(inputName.Text);

            slotMisc := ObjectToElement(roomSlotsOptional.Objects[selectUpgradeSlot.ItemIndex]);

            createRoomLayout(layer, targetHQ, targetRoomConfig, layoutName, csvPath, '', '', slotMisc, nil, nil);
        end;
        frm.free();




        // need
        // layoutName
        // upgradeNameSpaceless := '';
        // slotNameSpaceless := ''

        // function createRoomLayout(existingElem, hq: IInterface; layoutName, csvPath, upgradeNameSpaceless, slotNameSpaceless: string; upgradeSlot: IInterface): IInterface;

    end;

    function isRoomConstructionOrUpgrade(e: IInterface): boolean;
    begin
        if (hasKeywordByPath(e, SS2_Tag_HQ_ActionType_RoomUpgrade, 'KWDA')) then begin
            Result := true;
            exit;
        end;

        if (hasKeywordByPath(e, SS2_Tag_HQ_ActionType_RoomConstruction, 'KWDA')) then begin
            Result := true;
            exit;
        end;

        Result := false;
    end;

	procedure showRelevantDialog();
	var
		configScript: IInterface;
        scriptName: string;
	begin
		// what is targetElem?
        configScript := getFirstScript(targetElem);
        if(not assigned(configScript)) then begin
            showMultipleChoiceDialog();
            exit;
        end;

        scriptName := LowerCase(geevt(configScript, 'scriptName'));

        // room config?
		// configScript := getScript(targetElem, 'SimSettlementsV2:HQ:Library:MiscObjects:RequirementTypes:ActionTypes:HQRoomConfig');
		if(scriptName = 'simsettlementsv2:hq:library:miscobjects:requirementtypes:actiontypes:hqroomconfig') then begin
			AddMessage('Updating Room Config '+EditorID(targetElem));
			// loadHQs();
			targetHQ := getHqFromRoomConfig(configScript);
			loadFormsForHq(targetHQ);
			// loadForms();
			showRoomConfigDialog(targetElem);
			// a room config
			exit;
		end;

        // room upgrade?
        //if(assigned(configScript)) then begin
		if(scriptName = 'simsettlementsv2:hq:baseactiontypes:hqroomupgrade') then begin
			targetHQ := getHqFromRoomUpdate(configScript);
            loadFormsForHq(targetHQ);
            loadForRoomUpgade();


            AddMessage('Updating Room Upgrade '+EditorID(targetElem));
            // showRoomUpgradeDialog2(roomConfig, targetElem);
            showRoomUpgradeDialog(targetElem);


            exit;
        end;

        // room layout?

		if(scriptName = 'simsettlementsv2:hq:library:weapons:hqroomlayout') then begin
            AddMessage('Updating Room Layout '+EditorID(targetElem));
			targetHQ := getUniversalForm(configScript, 'workshopRef');
            loadFormsForHq(targetHQ);
            showLayoutUpgradeDialog(targetElem);
            exit;
        end;

        // maybe tech/other?
        //if(not isRoomConstructionOrUpgrade(targetElem)) then begin
            if(checkScriptExtendsCached(scriptName, 'SimSettlementsV2:HQ:Library:MiscObjects:RequirementTypes:HQAction')) then begin
                targetHQ := getHqFromRoomUpdate(configScript);
                loadFormsForHq(targetHQ);
                loadForRoomUpgade();
                AddMessage('Updating Tech Research/Other '+EditorID(targetElem));
                showTechResearchDialog(targetElem);
                exit;
            end;
        //end;

		showMultipleChoiceDialog();
	end;

    function checkScriptExtendsCached(scriptCheck, scriptCompare: string): boolean;
    var
        cacheLine: string;
        i, extendsState: integer;
        cacheSubEntry: TJsonObject;
    begin
        cacheSubEntry := currentCacheFile.O['extendsCache'];

        scriptCheck := LowerCase(scriptCheck);
        scriptCompare := LowerCase(scriptCompare);

        extendsState := cacheSubEntry.O[scriptCheck].I[scriptCompare];
        if(extendsState = 0) then begin
            // unknown
            Result := checkScriptExtends(scriptCheck, scriptCompare);
            if(Result) then begin
                extendsState := 2;
            end else begin
                extendsState := 1;
            end;

            cacheSubEntry.O[scriptCheck].I[scriptCompare] := extendsState;
            saveCacheFile();
        end else begin
            // 1 = false, 2 = true
            Result := extendsState = 2;
        end;
    end;

    function findScriptInElementByNameCached(e: IInterface; scriptName: String): IInterface;
    var
        curScript, scripts: IInterface;
        i: integer;
		curScriptName: string;
    begin
        Result := nil;
        scripts := ElementByPath(e, 'VMAD - Virtual Machine Adapter\Scripts');

        for i := 0 to ElementCount(scripts)-1 do begin
            curScript := ElementByIndex(scripts, i);

			curScriptName := GetElementEditValues(curScript, 'scriptName');

			if (checkScriptExtendsCached(curScriptName, scriptName)) then begin
				Result := curScript;
				exit;
			end;
        end;

    end;

	procedure cleanUp();
	begin
		cleanupSS2Lib();
		if(listHQRefs <> nil) then begin
			listHQRefs.free();
		end;
        listKeywordsConstruct.free();
        listKeywordsUpgrade.free();
        listKeywordsTech.free();

		listRoomShapes.free();
		listDepartmentObjects.free();
		listActionGroups.free();
		listRoomConfigs.free();
		listRoomFuncs.free();
		//listHqManagers.free();
		listModels.free();
		listModelsMisc.free();
		listRoomResources.free();
		listTechActionTypes.free();
		listPutDownSounds.free();
		if(currentCacheFile <> nil) then begin
			currentCacheFile.free();
		end;

		edidLookupCache.free();

		resourceLookupTable.free();
		progressBarStack.free();
		pexCleanUp();
	end;

    // Called after processing
    // You can remove it if script doesn't require finalization code
    function Finalize: integer;
    begin
		if(not assigned(targetElem)) then begin
			Result := 1;
			cleanUp();
			exit;
		end;

		// otherwise do all the stuff
		loadForms();

		showRelevantDialog();

        Result := 0;

		cleanUp();
    end;

end.