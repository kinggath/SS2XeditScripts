{
    Run on Room Config to update. Run on anything else to generate a new

	TODO:
	- Allow not selecting slot for a layout. generate a new KW then
	DONE:
    - Added direct layer updating
    - Use the unique part of the shape keyword instead of the full EDID for EDID generation
    - Use that unique part for model lookup:
            Misc Model = SS2C2\Interface\GNNRoomShapes\<Unique Portion of Room Shape Keyword>.nif
            COBJ Art Object = SS2C2_AO_RoomShape_<Unique Portion of Room Shape Keyword>
    - put RoomShape keyword and the UpgradeSlot keyword onto upgrade MISC
	- Allow updating of existing room updates
	- check what a script extends, not just the base
	- The RoomUpgrade action should be pointing at either SS2C2_HQ_ActionGroup_RoomBuildBaseUpgrades_GNN or SS2C2_HQ_ActionGroup_RoomUpgrade_GNN for its DepartmentHQActionGroup, depending on whether its targeting the Base slot or not.
	  For other HQs this might be different, so might be easier to just put a dropdown of all action groups for that HQ.
	- Different model for upgrade MISCs: from under Meshes\SS2C2\Interface\GNNRoomShapes. also optional
	- Probably shouldn't allow for no resources to be entered - as that will cause an unusable COBJ, and I believe an entry like this will cause the game to either crash or won't load the script properties of that object at all.
	- When reusing the typed in name for parts of editor IDs, looks like you are stripping spaces, which is good - should also strip special characters like '
	- Select Slot on layout-basis. Put the KW of the slot into TagKeyword
}
unit ImportHqRoom;
	uses 'SS2\SS2Lib'; // uses praUtil
	uses 'SS2\CobbLibrary';
	uses 'SS2\PexParser';

	const
		cacheFile = ProgramPath + 'Edit Scripts\SS2\HqRoomCache.json';

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
		listDepartmentObjects: TStringList;
		listActionGroups: TStringList;
		listRoomConfigs: TStringList;
		listRoomFuncs: TStringList;
		listModels: TStringList;
		listModelsMisc: TStringList;
		listRoomResources: TStringList;
		// other lists
		edidLookupCache: TStringList;
		resourceLookupTable: TJsonObject;
		// general stuff needed from master
		SS2_HQ_FauxWorkshop: IInterface;
		SS2_FLID_HQActions: IInterface;
		SS2_HQ_WorkshopRef_GNN: IInterface;
		WorkshopItemKeyword: IInterface;
		SS2_TF_HologramGNNWorkshopTiny: IInterface;
		SS2_HQ_Action_RoomUpgrade_Template: IInterface;
		SS2_HQRoomLayout_Template: IInterface;
		SS2_co_HQBuildableAction_GNN_RoomUpgrade_Template: IInterface;
		SS2_VirtualResourceCategory_Scrap: IInterface;
		SS2_VirtualResourceCategory_RareMaterials: IInterface;
		SS2_VirtualResourceCategory_OrganicMaterials: IInterface;
		SS2_VirtualResourceCategory_MachineParts: IInterface;
		SS2_VirtualResourceCategory_BuildingMaterials: IInterface;
		SS2_c_HQ_DailyLimiter_Scrap: IInterface;
        SS2_Tag_HQ_RoomIsClean: IInterface;
		// templates
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

    function getStringAfter(str, separator: string): string;
    var

        p: integer;
    begin

        p := Pos(separator, str);
        if(p <= 0) then begin
            Result := str;
            exit;
        end;

        p := p + length(separator);

        Result := copy(str, p, length(str)-p+1);
    end;

    function getRoomShapeKeywordFromConfig(roomConfig: IInterface): IInterface;
    var
        configScript: IInterface;
    begin
        configScript := getScript(roomConfig, 'SimSettlementsV2:HQ:Library:MiscObjects:RequirementTypes:ActionTypes:HQRoomConfig');
        // -> SS2C2_HQGNN_Action_AssignRoomConfig_GNN256BoxShape_Bathroom "Bathroom" [MISC:0401F0BE]
        Result := getScriptProp(configScript, 'RoomShapeKeyword');
    end;

    function getRoomShapeUniquePart(str: string): string;
    var
        edid: string;
        p: integer;
    begin
        Result := getStringAfter(str, '_Tag_RoomShape_');
    end;

	function StringRepeat(str: string; len: integer): string;
	var
		i: integer;
	begin
		Result := '';
		for i:=0 to len-1 do begin
			Result := Result + str;
		end;
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
			exit;
		end;

		list.addObject(str, elem);
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
            regex.RegEx := '^SS2_VirtualResource_([^_]+)_([^_]+)$';
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

		vrFormStr := FormToStr(vrElem);
		curEntry := resourceLookupTable.O[vrFormStr];

		curEntry.S[RESOURCE_COMPLEXITY_MINIMAL] :=  FormToStr(scrapElem);
		curEntry.S[RESOURCE_COMPLEXITY_CATEGORY]:= FormToStr(groupElem);
		curEntry.S[RESOURCE_COMPLEXITY_FULL] 	:= FormToStr(realElem);
	end;

	procedure registerSimpleResource(vrEdid, realEdid: string);
	begin
		registerResource(vrEdid, realEdid, realEdid, realEdid);
	end;

	procedure registerScrapResource(vrEdid, realEdid, groupEdid: string);
	begin
		registerResource(vrEdid, realEdid, groupEdid, 'SS2_c_HQ_SimpleResource_Scrap');
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
        scripts := ElementByPath(e, 'VMAD - Virtual Machine Adapter\Scripts');

        for i := 0 to ElementCount(scripts)-1 do begin
            curScript := ElementByIndex(scripts, i);

			if (assigned(getScriptProp(curScript, 'HQRef'))) then begin
				// might be
				curScriptName := GetElementEditValues(curScript, 'scriptName');

				if (checkScriptExtends(curScriptName, 'SimSettlementsV2:HQ:Library:Quests:SpecificHQManager')) then begin
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
			curRec := ElementByIndex(group, i);
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
			curRef := ReferencedByIndex(hq, i);
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
				AddMessage('Found '+FullPath(curRef));
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

				curHq := AbsStrToForm(hqString);
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

				Result := AbsStrToForm(managerString);
				exit;
			end;
		end;
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

	function getRoomConfigName(configMisc: IInterface): string;
	var
		edid, confName: string;
	begin
		edid := EditorID(configMisc);
		//edid := StringReplace(edid, 'SS2_HQGNN_Action_AssignRoomConfig_', '', [rfReplaceAll]);
		edid := regexReplace(edid, '[^_]+_HQ[^_]*_Action_AssignRoomConfig_', '');
		confName := GetElementEditValues(configMisc, 'FULL');

		Result := confName + ' (' + edid+')';
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
		AddMessage('Searching HQ for '+EditorID(e));
		curScript := getScript(e, 'SimSettlementsV2:HQ:Library:MiscObjects:RequirementTypes:ActionTypes:HQRoomConfig');

		primaryDepartment := getScriptProp(curScript, 'PrimaryDepartment');
		// primary department might be undefined...
		if(assigned(primaryDepartment)) then begin
			// this is a REFR
			linkedRefs := ElementByPath(primaryDepartment, 'Linked References');
			for i:=0 to ElementCount(linkedRefs)-1 do begin
				linkedEntry := ElementByIndex(linkedRefs, i);
				curKw := PathLinksTo(linkedEntry, 'Keyword/Ref');
				curRef := PathLinksTo(linkedEntry, 'Ref');

				if(EditorID(curKw) = 'WorkshopItemKeyword') then begin
					AddMessage('Found HQ '+EditorID(curRef)+' via linked ref');
					Result := curRef;
					exit;
				end;
			end;
		end;

		// otherwise try going via the upgrade
		RoomUpgradeSlots := getScriptProp(curScript, 'RoomUpgradeSlots');
		for i:=0 to ElementCount(RoomUpgradeSlots)-1 do begin
			curSlot := getObjectFromProperty(RoomUpgradeSlots, i);
			curSlotScript := getScript(curSlot, 'SimSettlementsV2:HQ:Library:MiscObjects:RequirementTypes:HQRoomUpgradeSlot_GNN');
			if(assigned(curSlotScript)) then begin
				AddMessage('Using default HQ because of _GNN script');
				Result := SS2_HQ_WorkshopRef_GNN;
				exit;
			end;
			curSlotScript := getScript(curSlot, 'simsettlementsv2:hq:library:miscobjects:requirementtypes:hqroomupgradeslot');
			if(assigned(curSlotScript)) then begin
				HQLocation := getScriptProp(curSlotScript, 'HQLocation');
				Result := findHqByLocation(HQLocation);
				if(assigned(Result)) then begin
					AddMessage('Found '+EditorID(AddMessage)+' in upgrade');
					exit;
				end;
			end;
		end;

		// finally, assume default HQ and hope for the best
		AddMessage('Using default HQ');
		Result := SS2_HQ_WorkshopRef_GNN;
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

			if(pos('HQ_ActionGroup_', edid) > 0) then begin

				if(edid <> 'SS2_HQ_ActionGroup_Template') then begin
					//SimSettlementsV2:HQ:Library:MiscObjects:ActionGroupTypes:DepartmentHQActionGroup
					curScript := findScriptInElementByName(curRec, 'SimSettlementsV2:HQ:Library:MiscObjects:HQActionGroup');
					if(assigned(curScript)) then begin
						curHq := getHqFromRoomActionGroup(curRec, curScript);
						// theoretically, this might be unset
						if(not assigned(curHq)) then begin
							curHq := SS2_HQ_WorkshopRef_GNN;
						end;

						curHqKey := FormToAbsStr(curHq);

						//AddMessage(BoolToStr(assigned(curRec)));
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
				curScript := getScript(curRec, 'SimSettlementsV2:HQ:Library:MiscObjects:RequirementTypes:ActionTypes:HQRoomConfig');
				if(assigned(curScript)) then begin
					// yes
					curName := getRoomConfigName(curRec);
					// addObjectDupIgnore(listRoomConfigs, curName, curRec);
					curFormID := getElementLocalFormId(curRec);
					curHq := getHqForRoomConfig(curRec);
					curHqKey := FormToAbsStr(curHq);
					currentCacheFile.O['files'].O[curFileName].O['HQData'].O[curHqKey].O['RoomConfigs'].S[curName] := IntToHex(curFormID, 8);
				end;
				continue;
			end;

			if(strStartsWithSS2(edid, 'HQRoomFunctionality_')) then begin
				curScript := getScript(curRec, 'SimSettlementsV2:HQ:Library:MiscObjects:HQRoomFunctionality');
				if(assigned(curScript)) then begin
					curName := GetElementEditValues(curRec, 'FULL');
					addObjectDupIgnore(listRoomFuncs, curName, curRec);
				end;
                continue;
				// SimSettlementsV2:HQ:Library:MiscObjects:HQRoomFunctionality
			end;

			if(strStartsWithSS2(edid, 'HQResourceToken_WorkEnergy_')) then begin
				addObjectDupIgnore(listRoomResources, GetElementEditValues(curRec, 'FULL'), curRec);
			end;
			updateProgress(i);
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
		startProgress('', 4);
		updateProgress(0);
		loadHQsFromFile(fromFile);
		updateProgress(1);
		loadKeywordsFromFile(fromFile);
		// loadActivatorsFromFile(fromFile);
		updateProgress(2);
		loadMiscsFromFile(fromFile);
		updateProgress(3);
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
		fileContents: TStringList;
		i, realFileAge: integer;
		hqKey, curFileName: string;
		filesEntry, filesEntries: TJsonObject;
	begin
		//cacheJson := TJsonObject.create();
		if(not assigned(currentCacheFile)) then begin
			currentCacheFile := TJsonObject.create;
		end;

		// hqKey := getTargetHqKey(); // we might not have targetHQ here
		//filesEntry := currentCacheFile.O['files'];
		//for i:=0 to currentCacheFile.O['files']


		currentCacheFile.S['DefaultHQ'] := FormToAbsStr(SS2_HQ_WorkshopRef_GNN);
		// simple stuff
		writeObjectListToCacheFile(listRoomShapes, 'RoomShapes');
		// writeObjectListToCacheFile(listRoomConfigs, 'RoomConfigs');
		writeObjectListToCacheFile(listRoomFuncs, 'RoomFuncs');
		writeObjectListToCacheFile(listRoomResources, 'RoomResources');

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

		fileContents := TStringList.create;

		//TEMP := currentCacheFile.toString();

		fileContents.add(currentCacheFile.toString());
		fileContents.saveToFile(cacheFile);
		fileContents.free();
		// cacheJson.free();

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
			curObj := getFormByFileAndFormID(forFile, curFormId);
			if(assigned(curObj)) then begin
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

			// this shouldn't actually be possible
			if(not FileExists(DataPath+curFileName)) then begin
				AddMessage('=== ERRROR: it seems that file '+curFileName+' doesn''t actually exist, despite being loaded???');
				continue;
			end;

			fileContainer := filesContainer.O[curFileName];

			// complex stuff
			fileHqContainer := fileContainer.O['HQData'];
			currentHqObj := fileHqContainer.O[hqKey];

			readFileDependentObjectList(curFileObj, listDepartmentObjects, currentHqObj.O['Departments']);
			readFileDependentObjectList(curFileObj, listActionGroups, 	   currentHqObj.O['ActionGroups']);
			readFileDependentObjectList(curFileObj, listRoomConfigs, 	   currentHqObj.O['RoomConfigs']);

		end;
	end;

	{
		This ensures that currentCacheFile exists, and attempts to fill it
	}
	function loadListsFromCache(forFiles: TStringList): TJsonObject;
	var
		listData: TStringList;

		i, j, eqPos: integer;
		curStr, formIdPart, fileNamePart, hqKey, curFileName: string;
		curFormId: cardinal;
		curObj, base, curFileObj, hqRef: IInterface;
		hqContainer, currentHqObj, filesContainer, fileContainer, fileHqContainer: TJsonObject;
		realFileAge: integer;
	begin
		Result := TJsonObject.create;
		Result.B['needModels'] := true;
		// Result.A['filesToReload']; // fill this with files which changed since the last time
		//currentCacheFile := TJsonObject.create();

		if(not FileExists(cacheFile)) then begin
			currentCacheFile := TJsonObject.create;

			// put all the masters in
			for i:=0 to forFiles.count-1 do begin
				curFileName := forFiles[i];
				Result.A['filesToReload'].add(curFileName);
			end;
			exit;
		end;

		AddMessage('Loading cache '+cacheFile);
		listData := TStringList.create;
		listData.loadFromFile(cacheFile);

		currentCacheFile := TJsonObject.parse(concatLines(listData));
		if(currentCacheFile = nil) then begin
			currentCacheFile := TJsonObject.create;
		end;
		listData.free();


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
			curFileObj  := ObjectToElement(forFiles.Objects[i]);

			AddMessage('Checking '+curFileName);

			// this shouldn't actually be possible
			if(not FileExists(DataPath+curFileName)) then begin
				AddMessage('=== ERRROR: it seems that file '+curFileName+' doesn''t actually exist, despite being loaded???');
				continue;
			end;

			fileContainer := filesContainer.O[curFileName];

			realFileAge := FileAge(DataPath+curFileName);

			if(realFileAge > fileContainer.I['timestamp']) then begin
				// file changed since
				AddMessage('File '+curFileName+' will be reloaded.');
				Result.A['filesToReload'].add(curFileName);
				// reset the object (or try to)
				filesContainer.clear();
			end else begin

				// simple stuff
				// readFileDependentObjectList(curFileObj, listHQRefs, 		fileContainer.O['HQs']);
				readFileDependentObjectList(curFileObj, listRoomShapes, 	fileContainer.O['RoomShapes']);
				//readFileDependentObjectList(curFileObj, listRoomConfigs, 	fileContainer.O['RoomConfigs']);
				readFileDependentObjectList(curFileObj, listRoomFuncs, 		fileContainer.O['RoomFuncs']);
				//readFileDependentObjectList(curFileObj, listHqManagers, 	fileContainer.O['HqManagers']);
				readFileDependentObjectList(curFileObj, listRoomResources, 	fileContainer.O['RoomResources']);


			end;

		end;

		readStringList(listModels, 	   currentCacheFile.O['assets'].A['ActivatorModels']);
		readStringList(listModelsMisc, currentCacheFile.O['assets'].A['MiscModels']);

		if (listModels.count > 0) or (listModelsMisc.count > 0) then begin
			// seems we have enough models
			Result.B['needModels'] := false;
		end;


		AddMessage('Cache loaded');
	end;

	function getMasterList(theFile: IInterface): TStringList;
	var
		curFile: IInterface;
		curFileName: string;
		i: integer;
	begin
		Result := TStringList.create();

		for i:=0 to MasterCount(targetFile)-1 do begin
			curFile := MasterByIndex(targetFile, i);
			curFileName := GetFileName(curFile);
			Result.addObject(curFileName, curFile);
		end;
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
		cacheResult := loadListsFromCache(masterList);



		filesToReload := cacheResult.A['filesToReload'];


		startProgress('Loading data...', filesToReload.count+1);
		if(filesToReload.count > 0) then begin
			for i:=0 to filesToReload.count-1 do begin
				updateProgress(i);
				curFileName := filesToReload.S[i];
				AddMessage('Reloading data from '+curFileName);
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
		SS2_co_HQBuildableAction_GNN_RoomUpgrade_Template := FindObjectByEdidWithError('SS2C2_co_HQBuildableAction_GNN_RoomUpgrade_Template');
		WorkshopItemKeyword := FindObjectByEdidWithError('WorkshopItemKeyword');
		SS2_HQGNN_Action_AssignRoomConfig_Template := FindObjectByEdidWithError('SS2C2_HQGNN_Action_AssignRoomConfig_Template');
		SS2_HQ_RoomSlot_Template := FindObjectByEdidWithError('SS2_HQ_RoomSlot_Template');
		SS2_HQ_RoomSlot_Template_GNN := FindObjectByEdidWithError('SS2C2_HQ_RoomSlot_Template_GNN');
		SS2_HQBuildableAction_Template := FindObjectByEdidWithError('SS2_HQBuildableAction_Template');

		SS2_HQ_RoomSlot_Template_GNN := FindObjectByEdidWithError('SS2C2_HQ_RoomSlot_Template_GNN');

		SS2_VirtualResourceCategory_Scrap 			  := FindObjectByEdidWithError('SS2_VirtualResourceCategory_Scrap');
		SS2_VirtualResourceCategory_RareMaterials 	  := FindObjectByEdidWithError('SS2_VirtualResourceCategory_RareMaterials');
		SS2_VirtualResourceCategory_OrganicMaterials  := FindObjectByEdidWithError('SS2_VirtualResourceCategory_OrganicMaterials');
		SS2_VirtualResourceCategory_MachineParts 	  := FindObjectByEdidWithError('SS2_VirtualResourceCategory_MachineParts');
		SS2_VirtualResourceCategory_BuildingMaterials := FindObjectByEdidWithError('SS2_VirtualResourceCategory_BuildingMaterials');

		SS2_c_HQ_DailyLimiter_Scrap := FindObjectByEdidWithError('SS2_c_HQ_DailyLimiter_Scrap');
		SS2_Tag_HQ_RoomIsClean := FindObjectByEdidWithError('SS2_Tag_HQ_RoomIsClean');

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
		listDepartmentObjects := TStringList.create;
		listActionGroups := TStringList.create;
		listRoomFuncs := TStringList.create;
		//listHqManagers := TStringList.create;
		listModels := TStringList.create;
		listModelsMisc := TStringList.create;
		listRoomResources := TStringList.create;
		listRoomConfigs := TStringList.create;

		resourceLookupTable := TJsonObject.create;
		edidLookupCache     := TStringList.create;


		listRoomFuncs.Sorted := true;
		listRoomResources.Sorted := true;
		listModels.Sorted := true;
		listModelsMisc.Sorted := true;
		listRoomConfigs.Sorted := true;

		//listHQRefs.Duplicates := dupIgnore;
		listRoomShapes.Duplicates := dupIgnore;
		listDepartmentObjects.Duplicates := dupIgnore;
		listActionGroups.Duplicates := dupIgnore;
		listRoomConfigs.Duplicates := dupIgnore;
		listRoomFuncs.Duplicates := dupIgnore;
		//listHqManagers.Duplicates := dupIgnore;
		listModels.Duplicates := dupIgnore;
		listModelsMisc.Duplicates := dupIgnore;
		listRoomResources.Duplicates := dupIgnore;
    end;

    // called for every record selected in xEdit
    function Process(e: IInterface): integer;
    begin
        Result := 0;

		if(not assigned(targetElem)) then begin
			targetElem := e;
			targetFile := GetFile(e);
		end;
    end;

	procedure updateRoomUpgrade1OkBtn(sender: TObject);
	var
		frm: TForm;
		btnOk: TButton;
		selectRoomConfig: TComboBox;
	begin
		frm := sender.parent;
		btnOk := TButton(frm.FindComponent('btnOk'));

        selectRoomConfig := TComboBox(frm.FindComponent('selectRoomConfig'));

		btnOk.enabled := (selectRoomConfig.ItemIndex >= 0);
	end;

	procedure updateRoomConfigOkBtn(sender: TObject);
	var
		inputName, inputPrefix: TEdit;
		btnOk: TButton;
		selectMainDep, selectRoomShape, selectActionGroup: TComboBox;
		frm: TForm;
    begin
		frm := sender.parent;
        inputName := TEdit(frm.FindComponent('inputName'));
        inputPrefix := TEdit(frm.FindComponent('inputPrefix'));
        selectMainDep := TComboBox(frm.FindComponent('selectMainDep'));
        selectRoomShape := TComboBox(frm.FindComponent('selectRoomShape'));
        selectActionGroup := TComboBox(frm.FindComponent('selectActionGroup'));

		btnOk := TButton(frm.FindComponent('btnOk'));

		if (trim(inputName.text) <> '') and (trim(inputPrefix.text) <> '') and (selectMainDep.ItemIndex >= 0) and (selectActionGroup.ItemIndex >= 0) and ((selectRoomShape.ItemIndex >= 0) or (trim(selectRoomShape.text) <> '')) then begin
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
	begin
		frm := sender.parent;
        listSlots := TListBox(frm.FindComponent('listSlots'));

		if(listSlots.ItemIndex >= 0) then begin
			listSlots.Items.delete(listSlots.ItemIndex);
		end;
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

	function getUpgradeSlot(existingMisc: IInterface; roomShape, roomName, slotName: string; forHq: IInterface): IInterface;
	var
		edidMisc, edidKw: string;
		slotMisc, slotKw, miscScript: IInterface;
	begin
		edidMisc := globalNewFormPrefix+'HQ_RoomSlot_'+roomShape+'_'+roomName+'_'+slotName;
		edidKw   := globalNewFormPrefix+'Tag_RoomSlot_'+roomShape+'_'+roomName+'_'+slotName;
		// MISC: SS2_HQ_RoomSlot_GNNLowerSouthwestNookShape_CommonArea_Base
		//       SS2_HQ_RoomSlot_<room shape>_<room name>_<slot name>

		// SS2_Tag_RoomSlot_GNNLowerSouthwestNookShape_CommonArea_Base [KYWD:0B00A3AB]
		// SS2_Tag_RoomSlot_<room shape>_<room name>_<slot name> [KYWD:0B00A3AB]

		if(not assigned(existingMisc)) then begin
			slotKw := getCopyOfTemplate(targetFile, keywordTemplate, edidKw);
			if(EditorID(forHq) = 'SS2_HQ_WorkshopRef_GNN') then begin
				slotMisc := getCopyOfTemplate(targetFile, SS2_HQ_RoomSlot_Template_GNN, edidMisc);
				miscScript := getScript(slotMisc, 'SimSettlementsV2:HQ:Library:MiscObjects:RequirementTypes:HQRoomUpgradeSlot_GNN');
			end else begin
				slotMisc := getCopyOfTemplate(targetFile, SS2_HQ_RoomSlot_Template, edidMisc);
				miscScript := getScript(slotMisc, 'simsettlementsv2:hq:library:miscobjects:requirementtypes:hqroomupgradeslot');
				setScriptProp(miscScript, 'HQLocation', getRefLocation(forHq));
			end;
			setScriptProp(miscScript, 'UpgradeSlotKeyword', slotKw);
		end else begin
			slotMisc := existingMisc;
			miscScript := getScript(slotMisc, 'SimSettlementsV2:HQ:Library:MiscObjects:RequirementTypes:HQRoomUpgradeSlot_GNN');
			if(not assigned(miscScript)) then begin
				miscScript := getScript(slotMisc, 'simsettlementsv2:hq:library:miscobjects:requirementtypes:hqroomupgradeslot');
			end;
			slotKw := getScriptProp(miscScript, 'UpgradeSlotKeyword');
		end;

		SetElementEditValues(slotMisc, 'FULL', slotName);
		SetElementEditValues(slotKw, 'FULL', slotName);

		Result := slotMisc;
	end;

	function createHqRoomConfig(existingElem: IInterface; forHq: IInterface; roomName: string; roomShapeKw: IInterface; roomShapeKwEdid: string; actionGroup: IInterface; primaryDepartment: IInterface; UpgradeSlots: TStringList): IInterface;
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
			roomShapeKw := getCopyOfTemplate(targetFile, keywordTemplate, roomShapeKwEdid);
		end;

		kwBase := getRoomShapeUniquePart(roomShapeKwEdid);
		if(kwBase = '') then begin
			kwBase := roomShapeKwEdid;
		end;

		if(not assigned(existingElem)) then begin
			configMiscEdid := globalNewFormPrefix+'HQ' + findHqNameShort(forHq)+'_Action_AssignRoomConfig_'+kwBase+'_'+roomNameSpaceless;
			configMisc := getCopyOfTemplate(targetFile, SS2_HQGNN_Action_AssignRoomConfig_Template, configMiscEdid);
			addKeywordByPath(configMisc, roomShapeKw, 'KWDA');

			roomConfigKeywordEdid := globalNewFormPrefix+'Tag_RoomConfig_'+kwBase+'_'+roomNameSpaceless;//<RoomShapeKeywordName>_<Name Entered Above>
			roomConfigKeyword := getCopyOfTemplate(targetFile, keywordTemplate, roomConfigKeywordEdid);
		end else begin
			configMisc := existingElem;
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
		setScriptProp(configMiscScript, 'PrimaryDepartment', primaryDepartment);

		roomConfigKw := getCopyOfTemplate(targetFile, keywordTemplate, globalNewFormPrefix+'Tag_RoomConfig_'+kwBase+'_'+roomNameSpaceless);

		setScriptProp(configMiscScript, 'RoomShapeKeyword', roomShapeKw);

		if(assigned(roomConfigKeyword)) then begin
			setScriptProp(configMiscScript, 'RoomConfigKeyword', roomConfigKeyword);
		end;

		roomUpgradeSlots := getOrCreateScriptProp(configMiscScript, 'RoomUpgradeSlots', 'Array of Object');
		clearProperty(roomUpgradeSlots);
		// RoomUpgradeSlots array of obj, generated from UpgradeSlots
		for i:=0 to UpgradeSlots.count-1 do begin
			curSlotName := cleanStringForEditorID(UpgradeSlots[i]);

			oldUpgradeMisc := ObjectToElement(UpgradeSlots.Objects[i]);

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
		end else begin
			dropDown.ItemIndex := -1;
		end;
	end;

	procedure setItemIndexByForm(dropDown: TComboBox; form: IInterface);
	var
		i, index: integer;
		curForm: IInterface;
	begin
		for i:=0 to dropDown.Items.count-1 do begin
			if(dropDown.Items.Objects[i] <> nil) then begin
				curForm := ObjectToElement(dropDown.Items.Objects[i]);
				if(FormsEqual(curForm, form)) then begin
					dropDown.ItemIndex := i;
					exit;
				end;
			end;
		end;

		dropDown.ItemIndex := -1;
	end;

	function GetRoomSlotName(slotMisc: IInterface): string;
	var
		miscScript, slotKw: IInterface;
	begin
		Result := GetElementEditValues(slotMisc, 'FULL');
		if(Result <> '') then exit;

		slotKw := findSlotKeywordFromSlotMisc(slotMisc);
		Result := GetElementEditValues(slotKw, 'FULL');
		if(Result <> '') then exit;

		// otherwise, mh
		Result := regexExtract(EditorID(slotMisc), '_([^_]+)$', 1);
		if(Result <> '') then exit;

		Result := EditorID(slotMisc);
	end;

	function getRoomUpgradeSlots(roomConfig: IInterface): TStringList;
	var
		configScript, RoomUpgradeSlots, curSlot: IInterface;
		i: integer;
		slotName: string;
	begin

		Result := TStringList.create();

		configScript := getScript(roomConfig, 'SimSettlementsV2:HQ:Library:MiscObjects:RequirementTypes:ActionTypes:HQRoomConfig');

		RoomUpgradeSlots := getScriptProp(configScript, 'RoomUpgradeSlots');

		for i:=0 to ElementCount(RoomUpgradeSlots)-1 do begin
			curSlot := getObjectFromProperty(RoomUpgradeSlots, i);

			slotName := GetRoomSlotName(curSlot);

			addObjectDupIgnore(Result, slotName, curSlot);
		end;

	end;

	function prependDummyEntry(list: TStringList; title: string): TStringList;
	var
		i: integer;
	begin
		Result := TStringList.create();
		Result.add(title);

		for i:=0 to list.count-1 do begin
			addObjectDupIgnore(Result, list[i], list.Objects[i]);
		end;
	end;

	function prependNoneEntry(list: TStringList): TStringList;
	begin
		Result := prependDummyEntry(list, '- NONE -');
	end;

	procedure addResourceToList(resIndex, cnt: Integer; box: TListBox);
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
		for i:=0 to box.Items.count-1 do begin
			resourceData := box.Items.Objects[i];
			if (resourceData.I['index'] = resIndex) then begin
				newCnt := resourceData.I['count']+cnt;
				resourceData.I['count'] := newCnt;
				Box.Items[i] := IntToStr(newCnt) + ' x ' + nameBase;
				exit;
			end;
		end;

		resourceData := TJsonObject.create();

		resourceData.I['index'] := resIndex;
		resourceData.I['count'] := cnt;

		box.Items.AddObject(IntToStr(cnt)+' x '+nameBase, resourceData);
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
			showRoomUpradeDialog2UpdateOk(resourceBox.parent);
		end;

		frm.free();
	end;

	procedure addResourceHandler(Sender: TObject);
	var
        frm: TForm;
		btnOk, btnCancel: TButton;
		selectResourceDropdown: TComboBox;
		inputName: TEdit;
		resultCode, nr: integer;
		resourceBox:TListBox;
	begin
		frm := CreateDialog('Add Resource', 300, 130);
		CreateLabel(frm, 10, 10, 'Select Resource to add');

		inputName := CreateInput(frm, 10, 28, '1');
		inputName.Width := 50;

		selectResourceDropdown := CreateComboBox(frm, 64, 28, 210, listRoomResources);
		selectResourceDropdown.Style := csDropDownList;
		selectResourceDropdown.Name := 'selectResourceDropdown';
		selectResourceDropdown.ItemIndex := 0;
		//listRoomResources

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

			resourceBox := TListBox(sender.parent.FindComponent('resourceBox'));
			addResourceToList(selectResourceDropdown.ItemIndex, nr, resourceBox);
			showRoomUpradeDialog2UpdateOk(resourceBox.parent);
		end;

		frm.free();
	end;

	procedure remResourceHandler(Sender: TObject);
	var
		resourceBox: TListBox;
		index: integer;
	begin
		resourceBox := TListBox(sender.parent.FindComponent('resourceBox'));
		if(resourceBox.ItemIndex < 0) then begin
			exit;
		end;

		resourceBox.Items.Objects[resourceBox.ItemIndex].free();
		resourceBox.Items.Delete(resourceBox.ItemIndex);
		showRoomUpradeDialog2UpdateOk(resourceBox.parent);
	end;

	procedure remRoomFuncHandler(Sender: TObject);
	var
		resourceBox: TListBox;
		index: integer;
	begin
		resourceBox := TListBox(sender.parent.FindComponent('roomFuncsBox'));
		if(resourceBox.ItemIndex < 0) then begin
			exit;
		end;

		resourceBox.Items.Delete(resourceBox.ItemIndex);
	end;

	procedure addRoomFuncHandler(Sender: TObject);
	var
        frm: TForm;
		btnOk, btnCancel: TButton;
		selectResourceDropdown: TComboBox;
		resultCode, nr: integer;
		resourceBox:TListBox;
	begin
		frm := CreateDialog('Add Room Function', 300, 130);
		CreateLabel(frm, 10, 10, 'Select Room Function to add');

		selectResourceDropdown := CreateComboBox(frm, 10, 28, 270, listRoomFuncs);
		selectResourceDropdown.Style := csDropDownList;
		selectResourceDropdown.Name := 'selectResourceDropdown';
		selectResourceDropdown.ItemIndex := 0;


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
			resourceBox := TListBox(sender.parent.FindComponent('roomFuncsBox'));

			// try to find existing
			if(resourceBox.Items.indexOf(listRoomFuncs[selectResourceDropdown.ItemIndex]) < 0) then begin
				resourceBox.Items.AddObject(listRoomFuncs[selectResourceDropdown.ItemIndex], listRoomFuncs.Objects[selectResourceDropdown.ItemIndex]);
			end;
			// addResourceToList(selectResourceDropdown.ItemIndex, nr, roomFuncsBox);
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

            // special stuff: we might have layoutData.S['existing'] := FormToStr(curLayout);
            if(layoutData.S['existing'] <> '') then begin
                existingLayer := StrToForm(layoutData.S['existing']);
                if(assigned(existingLayer)) then begin
                    oldFormLabel.Name := 'oldFormLabel';
                    oldFormLabel.Caption := 'Existing Layer: '+EditorID(existingLayer);
                end;
            end;

			selectedSlot := StrToForm(selectedSlotStr);
			setItemIndexByForm(selectUpgradeSlot, selectedSlot);

		end;

		layoutBrowseUpdateOk(btnOk);

		resultCode := frm.showModal();
		if(resultCode = mrYes) then begin
			layoutName := trim(inputName.Text);
			layoutPath := trim(inputPath.Text);

			// selectedSlot := nil;
			//if(selectUpgradeSlot.ItemIndex > 0) then begin
			selectedSlot := ObjectToElement(selectUpgradeSlot.Items.Objects[selectUpgradeSlot.ItemIndex]);
			//end;
			layoutDisplayName := getLayoutDisplayName(layoutName, layoutPath, selectedSlot);

            selectedSlotStr := FormToStr(selectedSlot);
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

		layoutsBox.Items.Objects[layoutsBox.ItemIndex].free();
		layoutsBox.Items.Delete(layoutsBox.ItemIndex);
		showRoomUpradeDialog2UpdateOk(layoutsBox.parent);
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
		selectUpgradeSlot, selectActionGroup: TComboBox;
		resourceBox, roomFuncsBox, layoutsBox: TListBox;
		durationNr: float;
		layoutsGroup, resourceGroup: TGroupBox;
	begin
		btnOk := TButton(sender.parent.FindComponent('btnOk'));

		inputName := TEdit(sender.parent.FindComponent('inputName'));
		inputPrefix := TEdit(sender.parent.FindComponent('inputPrefix'));
		inputDuration := TEdit(sender.parent.FindComponent('inputDuration'));

		selectUpgradeSlot := TComboBox(sender.parent.FindComponent('selectUpgradeSlot'));
		selectActionGroup := TComboBox(sender.parent.FindComponent('selectActionGroup'));

		resourceBox := TListBox(sender.parent.FindComponent('resourceBox'));
		if(resourceBox = nil) then begin
			resourceGroup := TGroupBox (sender.parent.FindComponent('resourceGroup'));
			resourceBox := TListBox(resourceGroup.FindComponent('resourceBox'));
		end;

		// roomFuncsBox := TListBox(sender.parent.FindComponent('roomFuncsBox'));
		layoutsBox := TListBox(sender.parent.FindComponent('layoutsBox'));
		if(layoutsBox = nil) then begin
			layoutsGroup := TGroupBox (sender.parent.FindComponent('layoutsGroup'));
			layoutsBox := TListBox(layoutsGroup.FindComponent('layoutsBox'));
		end;

		durationNr := tryToParseFloat(trim(inputDuration.Text));

		btnOk.enabled := (trim(inputName.Text) <> '') and (trim(inputPrefix.Text) <> '') and (durationNr > 0) and (selectUpgradeSlot.ItemIndex >= 0) and (selectActionGroup.ItemIndex >= 0) and (layoutsBox.Items.count > 0) and (resourceBox.Items.count > 0);

	end;

    function getModelArrayIndex(str: string; modelArray: TStringList): integer;
    var
        i: integer;
    begin
        for i:=0 to modelArray.count-1 do begin
            AddMessage('checking '+modelArray[i]+' in '+str);
            if(strEndsWithCI(str, modelArray[i])) then begin
                Result := i;
                exit;
            end;
        end;

        Result := 0;
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
            exit;
        end;

        for i:=0 to ElementCount(ResourceCost)-1 do begin
            curStruct := ElementByIndex(ResourceCost, i);
            {AddMessage('dump begin');
            dumpElem(curStruct);
            AddMessage('dump end');}
            curResObject := getStructMember(curStruct, 'Item');
            resCount     := getStructMember(curStruct, 'iCount');

            // now find the index
            resIndex := indexOfElement(listRoomResources, curResObject);
            // AddMessage('Found '+editorID(curREsObject)+' index '+IntToStr(resIndex));

            addResourceToList(resIndex, resCount, resourceBox);
        end;
    end;

    procedure fillRoomFunctionsFromExisting(roomFuncsBox: TListBox; script: IInterface);
    var
        i, roomFuncIndex: integer;
        ProvidedFunctionality, curRoomFunc: IInterface;
    begin
        ProvidedFunctionality := getScriptProp(script, 'ProvidedFunctionality');
        if(not assigned(ProvidedFunctionality)) then begin
            exit;
        end;

        for i:=0 to ElementCount(ProvidedFunctionality)-1 do begin
            curRoomFunc := getObjectFromProperty(ProvidedFunctionality, i);

            roomFuncIndex := indexOfElement(listRoomFuncs, curRoomFunc);

            roomFuncsBox.Items.AddObject(listRoomFuncs[roomFuncIndex], listRoomFuncs.Objects[roomFuncIndex]);
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
            curLayout := getObjectFromProperty(RoomLayouts, i);

            layoutName := GetElementEditValues(curLayout, 'FULL');

            selectedSlot := findSlotMiscFromLayout(curLayout);

            layoutData := TJsonObject.create();
            // I need name and slot
            layoutData.S['name'] := layoutName;
            layoutData.S['slot'] := FormToStr(selectedSlot);
            // resourceJson.S['path']
            layoutData.S['existing'] := FormToStr(curLayout);

            layoutPath := EditorID(curLayout);

            layoutDisplayName := getLayoutDisplayName(layoutName, layoutPath, selectedSlot);

            layoutsBox.Items.addObject(layoutDisplayName, layoutData);
        end;
    end;

	procedure showRoomUpgradeDialog2(targetRoomConfig, existingElem: IInterface);
	var
        frm: TForm;
		btnOk, btnCancel: TButton;
		resultCode, curY, secondRowOffset: integer;
		// roomSlots: TStringList;
		selectUpgradeSlot, selectDepartment, selectModel, selectMiscModel, selectActionGroup: TComboBox;
		assignDepAtEnd, assignDepAtStart, disableClutter, disableGarbarge, defaultConstMarkers, realTimeTimer: TCheckBox;
		doRegisterCb: TCheckBox;
		departmentList, modelList, modelListMisc: TStringList;
		inputName, inputPrefix, inputDuration: TEdit; ///Duration: Float - default to 24

		resourceGroup: TGroupBox;
		resourceBox: TListBox;
		resourceAddBtn, resourceRemBtn, resourceEdtBtn: TButton;

		roomFuncsGroup: TGroupBox;
		roomFuncsBox: TListBox;
		roomFuncAddBtn, roomFuncRemBtn: TButton;

		layoutsGroup: TGroupBox;
		layoutsBox: TListBox;
		layoutsAddBtn, layoutsRemBtn, layoutsEdtBtn: TButton;

		modelStr, modelStrMisc, upgradeName, windowCaption, shapeKeywordBase, MiscModelFilename, artObjEdid: string;
		targetDepartment: IInterface;

		roomUpgradeMisc, roomUpgradeActi: IInterface;
		upgradeDuration: float;

		roomShapeKeyword, upgradeSlot, actionGroup: IInterface;

        // existing stuff
        existingMiscScript, existingActi, existingActiScript: IInterface;

        modelIndex: integer;
	begin
		// load the slots for what we have
        currentListOfUpgradeSlots := getRoomUpgradeSlots(targetRoomConfig);

		secondRowOffset := 300;

        windowCaption := 'Generating Room Upgrade';
        if(assigned(existingElem)) then begin
            windowCaption := 'Updating Room Upgrade';

            existingMiscScript := getScript(existingElem, 'SimSettlementsV2:HQ:BaseActionTypes:HQRoomUpgrade');

            // try to find the acti, too
            existingActi := findRoomUpgradeActivator(existingElem);
            AddMessage('Found corresponiding acti '+editorID(existingActi));
            existingActiScript := getScript(existingActi, 'SimSettlementsV2:HQ:Library:ObjectRefs:HQWorkshopItemActionTrigger');
        end;

        roomShapeKeyword := getRoomShapeKeywordFromConfig(targetRoomConfig);
        shapeKeywordBase := getRoomShapeUniquePart(EditorID(roomShapeKeyword));

        MiscModelFilename := shapeKeywordBase+'.nif';//SS2C2\Interface\GNNRoomShapes\<Unique Portion of Room Shape Keyword>.nif
        ArtObjEdid := 'SS2C2_AO_RoomShape_'+shapeKeywordBase;

		frm := CreateDialog(windowCaption, 620, 580);// x=+30 y=+20
		curY := 0;
		//if(not assigned(existingElem)) then begin
        CreateLabel(frm, 10, 10+curY, 'HQ: '+EditorID(targetHQ)+'.');
        CreateLabel(frm, 10, 28+curY, 'Room Config: '+EditorID(targetRoomConfig));
		//end;
		curY := curY + 42;
		CreateLabel(frm, 10, 10+curY, 'Name:');
		inputName := CreateInput(frm, 100, 8+curY, '');
		inputName.Name := 'inputName';
		inputName.Text := '';
		inputName.width := 200;
		inputName.onChange := showRoomUpradeDialog2UpdateOk;

		CreateLabel(frm, secondRowOffset+10, 10+curY, 'EditorID Prefix:');
		inputPrefix := CreateInput(frm, secondRowOffset+100, 8+curY, '');
		inputPrefix.Name := 'inputPrefix';
		inputPrefix.Text := '';
		inputPrefix.width := 200;
		inputPrefix.onChange := showRoomUpradeDialog2UpdateOk;


		curY := curY + 24;

		modelListMisc := prependNoneEntry(listModelsMisc);
		modelList := prependNoneEntry(listModels);
		//selectActionGroup
		CreateLabel(frm, 10, 10+curY, 'Action Group:');
		selectActionGroup := CreateComboBox(frm, 100, 8+curY, 500, listActionGroups);
		selectActionGroup.Style := csDropDownList;
		selectActionGroup.Name := 'selectActionGroup';
		selectActionGroup.ItemIndex := -1;
		selectActionGroup.onChange := showRoomUpradeDialog2UpdateOk;

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
		CreateLabel(frm, 10, 10+curY, 'Upgrade slot:');
		selectUpgradeSlot := CreateComboBox(frm, 100, 8+curY, 200, currentListOfUpgradeSlots);
		selectUpgradeSlot.Style := csDropDownList;
		selectUpgradeSlot.Name := 'selectUpgradeSlot';
		selectUpgradeSlot.onChange := showRoomUpradeDialog2UpdateOk;


		// selectUpgradeSlot.onChange := updateRoomUpgrade1OkBtn;
		curY := curY + 42;
		assignDepAtStart := CreateCheckbox(frm, 10, curY, 'Assign department to room at start');
        assignDepAtStart.Checked := true;
		//curY := curY + 16;
		assignDepAtEnd := CreateCheckbox(frm, 10, curY + 16, 'Assign department to room at end');
		defaultConstMarkers := CreateCheckbox(frm, 10, curY + 32, 'Use default construction markers');
		defaultConstMarkers.Checked := true;
		//curY := curY + 16;
		disableClutter := CreateCheckbox(frm, 250, curY, 'Disable clutter on completion');
		disableClutter.Checked := true;
		disableGarbarge:= CreateCheckbox(frm, 250, curY +16, 'Disable garbage on completion');
		disableGarbarge.Checked := true;
		realTimeTimer:= CreateCheckbox(frm, 250, curY +32, 'Real-Time Timer');
		realTimeTimer.Checked := false;

		curY := curY + 50;

		CreateLabel(frm, 10, 10+curY, 'Duration (hours):');
		inputDuration := CreateInput(frm, 150, 8+curY, '24.0');
		inputDuration.width := 200;
		inputDuration.Name := 'inputDuration';
		inputDuration.Text := '24.0';
		inputDuration.onChange := showRoomUpradeDialog2UpdateOk;

		curY := curY + 32;
		CreateLabel(frm, 10, curY+4, 'Give control to department:');
		departmentList := prependNoneEntry(listDepartmentObjects);

		selectDepartment := CreateComboBox(frm, 150, curY, 200, departmentList);
		selectDepartment.Style := csDropDownList;
		selectDepartment.Name := 'selectDepartment';
		selectDepartment.ItemIndex := 0;
		//selectMainDep.onChange := updateRoomConfigOkBtn;

		curY := curY + 36;
		// test

		//CreateLabel();
		resourceGroup := CreateGroup(frm, 10, curY, 290, 88, 'Resources');
		resourceGroup.Name := 'resourceGroup';

		resourceBox := CreateListBox(resourceGroup, 8, 16, 200, 72, nil);
		resourceBox.Name := 'resourceBox';

		resourceBox.ondblclick := editResourceHandler;

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

		roomFuncsBox := CreateListBox(roomFuncsGroup, 8, 16, 200, 72, nil);
		roomFuncsBox.Name := 'roomFuncsBox';
		//roomFuncsBox.onChange := showRoomUpradeDialog2UpdateOk;



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
		//layoutsBox.onChange := showRoomUpradeDialog2UpdateOk;
		layoutsBox.ondblclick := editLayoutHandler;

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

        // update fields if updating
        if(assigned(existingElem)) then begin
            inputPrefix.Text := findEditorIdPrefix(existingElem);

            inputName.Text := GetElementEditValues(existingElem, 'FULL');
            modelStrMisc := GetElementEditValues(existingElem, 'Model\MODL');
            selectMiscModel.ItemIndex := getModelArrayIndex(modelStrMisc, selectMiscModel.Items);



            assignDepAtStart.Checked    := getScriptPropDefault(existingMiscScript, 'bAssignDepartmentToRoomAtStart', assignDepAtStart.Checked);
            assignDepAtEnd.Checked      := getScriptPropDefault(existingMiscScript, 'bAssignDepartmentToRoomAtEnd', assignDepAtEnd.Checked);
            disableClutter.Checked      := getScriptPropDefault(existingMiscScript, 'bDisableClutter_OnCompletion', disableClutter.Checked);
            disableGarbarge.Checked     := getScriptPropDefault(existingMiscScript, 'bDisableGarbage_OnCompletion', disableGarbarge.Checked);
            defaultConstMarkers.Checked := getScriptPropDefault(existingMiscScript, 'bUseDefaultConstructionMarkers', defaultConstMarkers.Checked);
            realTimeTimer.Checked       := getScriptPropDefault(existingMiscScript, 'RealTimeTimer', realTimeTimer.Checked);

            inputDuration.Text := floatToStr(getScriptPropDefault(existingMiscScript, 'Duration', 24.0));

            actionGroup := getScriptProp(existingMiscScript, 'DepartmentHQActionGroup');
            selectActionGroup.ItemIndex := indexOfElement(listActionGroups, actionGroup);

            upgradeSlot := getScriptProp(existingMiscScript, 'TargetUpgradeSlot');
            selectUpgradeSlot.ItemIndex := indexOfElement(currentListOfUpgradeSlots, upgradeSlot);

            targetDepartment := getScriptProp(existingMiscScript, 'NewDepartmentOnCompletion');
            if(assigned(targetDepartment)) then begin
                selectDepartment.ItemIndex := indexOfElement(selectDepartment.Items, targetDepartment);
            end;
            //setScriptProp(script, 'NewDepartmentOnCompletion', targetDepartment);
            {existingActi := findRoomUpgradeActivator(existingElem);
            existingActiScript := getScript(existingActi, 'SimSettlementsV2:HQ:Library:ObjectRefs:HQWorkshopItemActionTrigger');}

            modelStr := GetElementEditValues(existingActi, 'Model\MODL');
            selectModel.ItemIndex := getModelArrayIndex(modelStr, selectModel.Items);

            // now the hard parts
            fillResourceItemsFromExisting(resourceBox, existingMiscScript);
            fillRoomFunctionsFromExisting(roomFuncsBox, existingMiscScript);
            // and the hardedest
            fillLayoutsFromExisting(layoutsBox, existingMiscScript);
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

			upgradeName := trim(inputName.Text);
			upgradeDuration := tryToParseFloat(inputDuration.Text);
			upgradeSlot := ObjectToElement(currentListOfUpgradeSlots.Objects[selectUpgradeSlot.ItemIndex]);

			actionGroup := ObjectToElement(listActionGroups.Objects[selectActionGroup.ItemIndex]);

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
				actionGroup
			);

			roomUpgradeActi := createRoomUpgradeActivator(existingActi, roomUpgradeMisc, targetHQ, upgradeName, modelStr);

			createRoomUpgradeCOBJs(roomUpgradeActi, targetHQ, getActionAvailableGlobal(roomUpgradeMisc), upgradeName, resourceBox.Items, upgradeDuration, ArtObjEdid);

			if(doRegisterCb.checked) then begin
				// register
				AddMessage('Registering Room Upgrade');
				registerAddonContent(targetFile, roomUpgradeMisc, SS2_FLID_HQActions);
			end;
			AddMessage('Room Upgrade generation complete!');
		end;


		// cleanup objects?
		freeStringListObjects(resourceBox.Items);
		freeStringListObjects(layoutsBox.Items);

		currentListOfUpgradeSlots.free();
		modelList.free();
		departmentList.free();
		frm.free();
	end;

	function createRoomLayout(existingElem, hq: IInterface; layoutName, csvPath, upgradeNameSpaceless, slotNameSpaceless: string; upgradeSlot: IInterface): IInterface;
	var
		resultEdid, layoutNameSpaceless, curLine, curEditorId, curFileName: string;
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
            resultEdid := globalNewFormPrefix+'HQRoomLayout_'+upgradeNameSpaceless+'_'+slotNameSpaceless+'_'+layoutNameSpaceless;
            Result := getCopyOfTemplate(targetFile, SS2_HQRoomLayout_Template, resultEdid);
        end else begin
            Result := existingElem;
        end;

		resultScript := getScript(Result, 'SimSettlementsV2:HQ:Library:Weapons:HQRoomLayout');

		SetElementEditValues(Result, 'FULL', layoutName);

		// put in the slot KW
		slotKw := findSlotKeywordFromSlotMisc(upgradeSlot);

		setScriptProp(resultScript, 'TagKeyword', slotKw);
		setScriptProp(resultScript, 'workshopRef', hq);

		// now, the hard part
		spawnData := TJsonObject.create();
		//spawnData.O['offset']['pos'] := newVector(0,0,0);
		//spawnData.O['offset']['rot'] := newVector(0,0,0);

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

			 // pos, rot, scale
			if (csvCols.count < 8) or
				(csvCols.Strings[0] = '') or
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
					spawnObj.S['Form'] := FormToStr(curForm);
				end;

				spawnObj.O['pos'] := newVector(StrToFloat(csvCols.Strings[1]), StrToFloat(csvCols.Strings[2]), StrToFloat(csvCols.Strings[3]));
				spawnObj.O['rot'] := newVector(StrToFloat(csvCols.Strings[4]), StrToFloat(csvCols.Strings[5]), StrToFloat(csvCols.Strings[6]));
				spawnObj.F['scale'] := StrToFloat(csvCols.Strings[7]);

				if(csvCols.count >= 8) then begin
					if(csvCols.Strings[8] <> '') then begin
						spawnObj.F['extraData'] := StrToFloat(csvCols.Strings[8]);
					end;

					if(csvCols.count >= 10) then begin
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
		// AddMessage(spawnData.toString());
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

				spawnObj.F['posX'] := rotatedData.O['pos'].F['x'];
				spawnObj.F['posY'] := rotatedData.O['pos'].F['y'];
				spawnObj.F['posZ'] := rotatedData.O['pos'].F['z'];
				spawnObj.F['rotX'] := rotatedData.O['rot'].F['x'];
				spawnObj.F['rotY'] := rotatedData.O['rot'].F['y'];
				spawnObj.F['rotZ'] := rotatedData.O['rot'].F['z'];
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
			formElem := StrToForm(itemData.S['Form']);
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
		vrFormStr := FormToStr(vrResource);
		resultStr := resourceLookupTable.O[vrFormStr].S[complexity];
		if(resultStr = '') then begin
			exit;
		end;

		Result := StrToForm(resultStr);
	end;

	function getResourcesGrouped(resources: TStringList; resourceComplexity: integer): TJsonObject;
	var
		i, resIndex, count, numScrap: integer;
		resourceData: TJsonObject;
		curResource, realResource: IInterface;
		sig, resourceStr, inputResourceId: string;
	begin
        numScrap := 0;
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
                if(strStartsWith(inputResourceId, 'SS2_VirtualResource_')) then begin
                    numScrap := numScrap + count;
                end;
            end;

			resourceStr := FormToStr(realResource);
			Result.I[resourceStr] := Result.I[resourceStr] + count;
		end;

        if(numScrap > 0) then begin
            resourceStr := FormToStr(SS2_c_HQ_DailyLimiter_Scrap);
			Result.I[resourceStr] := numScrap;
        end;
	end;

    function getCobjConditionValue(conditions: IInterface): integer;
    var
        i: integer;
        cond: IInterface;
    begin
        for i:=0 to ElementCount(conditions)-1 do begin
            cond := ElementByIndex(conditions, i);
            glob := PathLinksTo(cond, 'CTDA\Global');//SS2_Settings_ResourceComplexity [GLOB:03020B07]
            if(EditorID(glob) = 'SS2_Settings_ResourceComplexity') then begin
                Result := PathLinksTo(complexityCondition, 'CTDA\Comparison Value');
                exit;
            end;
        end;

        Result := -1;
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
                    conditions := ElementByPath(Result, 'Conditions');
                    if(getCobjConditionValue(conditions) = resourceComplexity) then begin
                        Result := curRef;
                    end;
                end;
            end;
        end;

        Result := nil;
    end;

	function createRoomUpgradeCOBJ(edidBase, descriptionText: string; resourceComplexity: integer; acti, availableGlobal: IInterface; resources: TStringList; artObject: IInterface): IInterface;
	var
		edid, curName: string;
		i, count, totalCount: integer;
		availCondition, complexityCondition, fvpa, component, conditions: IInterface;
		cobjResources: TJsonObject;
	begin
        // try to find the cobj
        Result := findRoomUpgradeCOBJ(resourceComplexity, acti);

        if(not assigned(Result)) then begin
            edid := edidBase + '_' + IntToStr(resourceComplexity);
            Result := getCopyOfTemplate(targetFile, SS2_co_HQBuildableAction_GNN_RoomUpgrade_Template, edid);
        end;

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

			setPathLinksTo(component, 'Component', StrToForm(curName));
			SetElementEditValues(component, 'Count', IntToStr(count));
		end;

		cobjResources.free();
	end;

	procedure createRoomUpgradeCOBJs(acti, forHq, availableGlobal: IInterface; upgradeName: string; resources: TStringList; completionTime: float; ArtObjEdid: string);
	var
		cobj1, cobj2, cobj3, artObject: IInterface;
		edidBase, descriptionText, upgradeNameSpaceless: string;
		numDays: float;
	begin
		descriptionText := upgradeName+' | Completion Time: ';

		upgradeNameSpaceless := cleanStringForEditorID(upgradeName);
		numDays := round(completionTime / 24 * 10) / 10;
		if(floatEquals(numDays, 1)) then begin
			descriptionText := descriptionText + '1 Day';
		end else begin
			descriptionText := descriptionText + FloatToStr(numDays) + ' Days';
		end;

        artObject := nil;

        if(ArtObjEdid <> '') then begin
            artObject := findObjectByEdid(ArtObjEdid);
        end;

        // now, we could have these 3 cobjs already

		edidBase := globalNewFormPrefix+'HQ'+findHqNameShort(forHq)+'_BuildableAction_'+upgradeNameSpaceless;
		cobj1 := createRoomUpgradeCOBJ(edidBase, descriptionText, RESOURCE_COMPLEXITY_MINIMAL,  acti, availableGlobal, resources, artObject);
		cobj2 := createRoomUpgradeCOBJ(edidBase, descriptionText, RESOURCE_COMPLEXITY_CATEGORY, acti, availableGlobal, resources, artObject);
		cobj3 := createRoomUpgradeCOBJ(edidBase, descriptionText, RESOURCE_COMPLEXITY_FULL, 	acti, availableGlobal, resources, artObject);

	end;

	function createRoomUpgradeActivator(existingElem, roomUpgradeMisc, forHq: IInterface; upgradeName, modelStr: string): IInterface;
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
            edid := globalNewFormPrefix+'HQ'+findHqNameShort(forHq)+'_BuildableAction_'+upgradeNameSpaceless;
            // SS2_HQBuildableAction_Template
            Result := getCopyOfTemplate(targetFile, SS2_HQBuildableAction_Template, edid);
        end else begin
            Result := existingElem;
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
		actionGroup: IInterface): IInterface;
	var
		upgradeResult: IInterface;
		upgradeNameSpaceless, slotNameSpaceless, upgradeEdid, ActionAvailableGlobalEdid, HqName: string;
		script, roomCfgScript, ActionAvailableGlobal: IInterface;
		i, resIndex, resCount: integer;
		ResourceCost, ProvidedFunctionality, RoomLayouts, curResObject, curRoomFunc, newStruct, RoomRequiredKeywords, UpgradeSlotKeyword: IInterface;
		resourceJson: TJsonObject;
		curLayout: IInterface;
		curLayoutName, curLayoutPath, selectedSlotStr: string;
		upgradeSlotLayout, roomShapeKeyword, upgradeSlotKw, oldUpgradeSlotKw, oldUpgradeSlot: IInterface;
	begin
		HqName := findHqNameShort(targetHq);
		slotNameSpaceless := cleanStringForEditorID(getElementEditValues(upgradeSlot, 'FULL'));

		upgradeNameSpaceless := cleanStringForEditorID(upgradeName);

        if(not assigned(existingElem)) then begin
            upgradeEdid := globalNewFormPrefix+'HQ'+HqName+'_Action_RoomUpgrade_' + upgradeNameSpaceless; //configMiscEdid := 'SS2_HQ' + findHqNameShort(forHq)+'_Action_AssignRoomConfig_'+kwBase+'_'+roomNameSpaceless;
            upgradeResult := getCopyOfTemplate(targetFile, SS2_HQ_Action_RoomUpgrade_Template, upgradeEdid);
        end else begin
            upgradeResult := existingElem;
        end;

		if(modelStr <> '') then begin
			ensurePath(upgradeResult, 'Model\MODL');
			SetElementEditValues(upgradeResult, 'Model\MODL', modelStr);
		end;

		setPathLinksTo(upgradeResult, 'PTRN', SS2_TF_HologramGNNWorkshopTiny);

		SetElementEditValues(upgradeResult, 'FULL', upgradeName);

		script := getScript(upgradeResult, 'SimSettlementsV2:HQ:BaseActionTypes:HQRoomUpgrade');

		setScriptProp(script, 'bAssignDepartmentToRoomAtStart', assignAtStart);
		setScriptProp(script, 'bAssignDepartmentToRoomAtEnd', assignAtEnd);
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

        if(not assigned(existingElem)) then begin
            // make ActionAvailableGlobal
            // if updating, assume this exists already
            ActionAvailableGlobalEdid := globalNewFormPrefix+'HQActionAvailable_'+HqName+'_'+upgradeNameSpaceless;
            ActionAvailableGlobal := getCopyOfTemplate(targetFile, versionGlobalTemplate, ActionAvailableGlobalEdid);
            // how do I remove the CONST flag?
            SetElementEditValues(ActionAvailableGlobal, 'Record Header\Record Flags\Constant', '0');
            SetElementEditValues(ActionAvailableGlobal, 'FLTV', '0');

            setScriptProp(script, 'ActionAvailableGlobal', ActionAvailableGlobal);
        end;

        roomShapeKeyword := getRoomShapeKeywordFromConfig(targetRoomConfig);

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

		ProvidedFunctionality := getOrCreateScriptPropArrayOfObject(script, 'ProvidedFunctionality');

        // clear the property if we're updating
        if(assigned(existingElem)) then begin
            clearProperty(ProvidedFunctionality);
        end;

		for i:=0 to roomFuncs.count-1 do begin
			curRoomFunc := ObjectToElement(roomFuncs.Objects[i]);
			appendObjectToProperty(ProvidedFunctionality, curRoomFunc);
		end;

		hasRelativeCoordinateLayout   := false;
		hasNonRelativeCoordinateLayout:= false;

        RoomLayouts := getOrCreateScriptPropArrayOfObject(script, 'RoomLayouts');
        if(assigned(existingElem)) then begin
            clearProperty(RoomLayouts);

            updateExistingLayouts(targetHq, RoomLayouts, layouts, upgradeNameSpaceless, slotNameSpaceless);

        end else begin
            // create layouts from scratch
            for i:=0 to layouts.count-1 do begin
                resourceJson := TJsonObject(layouts.Objects[i]);

                curLayoutName := resourceJson.S['name'];
                curLayoutPath := resourceJson.S['path'];
                selectedSlotStr := resourceJson.S['slot'];
                upgradeSlotLayout := StrToForm(selectedSlotStr);

                curLayout := createRoomLayout(nil, targetHq, curLayoutName, curLayoutPath, upgradeNameSpaceless, slotNameSpaceless, upgradeSlotLayout);

                appendObjectToProperty(RoomLayouts, curLayout);
            end;
		end;

		if(hasRelativeCoordinateLayout and hasNonRelativeCoordinateLayout) then begin
			AddMessage('=== WARNING: some but not all layouts have a RoomExportHelper. This is probably a mistake, they should either all have it, or none should.');
		end;

		Result := upgradeResult;
	end;

    procedure updateExistingLayouts(targetHq, RoomLayouts: IInterface; layouts: TStringList; upgradeNameSpaceless, slotNameSpaceless: string);
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
                curLayout := StrToForm(layoutStr);
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
                curLayout := StrToForm(layoutStr);
            end;

            upgradeSlotLayout := StrToForm(curJsonData.S['slot']);

            if(assigned(curLayout)) then begin
                // updating
                AddMessage('Updating '+EditorID(curLayout));
                newLayout := createRoomLayout(curLayout, targetHq, curJsonData.S['name'], curJsonData.S['path'], upgradeNameSpaceless, slotNameSpaceless, upgradeSlotLayout);

            end else begin
                // creating new
                // do we have some to recycle?
                if(recycleLayouts.count > 0) then begin
                    curLayout := ObjectToElement(recycleLayouts.Objects[0]);
                    recycleLayouts.delete(0);
                end;
                if(curJsonData.S['path'] <> '') then begin
                    AddMessage('Generating layout. Using recycled? '+BoolToStr(curLayout));
                    newLayout := createRoomLayout(curLayout, targetHq, curJsonData.S['name'], curJsonData.S['path'], upgradeNameSpaceless, slotNameSpaceless, upgradeSlotLayout);
                    newLayouts.addObject(EditorID(newLayout), newLayouts);
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
        for i:=0 to recycleLayouts.count-1 do begin
            AddMessage('RECYCLING '+recycleLayouts[i]);
            curLayout := ObjectToElement(recycleLayouts.Objects[i]);
            deleteScriptProps(curLayout);
            SetElementEditValues(curLayout, 'FULL', 'Deleted Layout #'+IntToStr(i));
        end;

        prevLayouts.free();
        recycleLayouts.free();
        usedLayouts.free();
        newLayouts.free();
    end;

	function getActionAvailableGlobal(upgradeMisc: IInterface): IInterface;
	var
		script: IInterface;
	begin
		script := getScript(upgradeMisc, 'SimSettlementsV2:HQ:BaseActionTypes:HQRoomUpgrade');
		Result := getScriptProp(script, 'ActionAvailableGlobal');
	end;

    function findRoomConfigFromSlotMisc(slot: IInterface): IInterface;
    var
        i, numRefs: integer;
        curRef, refScript, RoomUpgradeSlots: IInterface;
    begin
        for i:=0 to ReferencedByCount(slot)-1 do begin
            curRef := ReferencedByIndex(slot, i);
            refScript := getScript(curRef, 'SimSettlementsV2:HQ:Library:MiscObjects:RequirementTypes:ActionTypes:HQRoomConfig');
            if(assigned(refScript)) then begin
                RoomUpgradeSlots := getScriptProp(refScript, 'RoomUpgradeSlots');
                if(hasObjectInProperty(RoomUpgradeSlots, slot)) then begin
                    AddMessage('Found '+EditorID(curRef));
                    Result := curRef;
                    exit;
                end;
            end;
        end;
    end;

    function findSlotKeywordFromSlotMisc(slotMisc: IInterface): IInterface;
    var
        curScript: IInterface;
    begin
        Result := nil;

        curScript := getScript(slotMisc, 'SimSettlementsV2:HQ:Library:MiscObjects:RequirementTypes:HQRoomUpgradeSlot_GNN');
        if(not assigned(curScript)) then begin
            curScript := getScript(slotMisc, 'SimSettlementsV2:HQ:Library:MiscObjects:RequirementTypes:HQRoomUpgradeSlot');
        end;

        if(assigned(curScript)) then begin
            Result := getScriptProp(curScript, 'UpgradeSlotKeyword');
        end;
    end;

    function findSlotMiscFromLayout(layout: IInterface): IInterface;
    var
        layoutScript, TagKeyword, curRef, UpgradeSlotKeyword: IInterface;
        i: integer;
    begin
        layoutScript := getScript(layout, 'SimSettlementsV2:HQ:Library:Weapons:HQRoomLayout');
        TagKeyword := getScriptProp(layoutScript, 'TagKeyword');
        // find the misc from the kw
        for i:=0 to ReferencedByCount(TagKeyword)-1 do begin
            curRef := ReferencedByIndex(TagKeyword, i);
            if(signature(curRef) = 'MISC') then begin
                UpgradeSlotKeyword := findSlotKeywordFromSlotMisc(curRef);

                if(equals(UpgradeSlotKeyword, TagKeyword)) then begin
                    Result := curRef;
                    exit;
                end;

            end;
        end;

        Result := nil;
    end;

    function findRoomConfigFromLayout(layout: IInterface): IInterface;
    var
        slotMisc: IInterface;
    begin
        slotMisc := findSlotMiscFromLayout(layout);
        Result := findRoomConfigFromSlotMisc(slotMisc);
        if(assigned(Result)) then begin
            AddMessage('Found '+EditorID(Result)+' in layout');
            exit;
        end;

        Result := nil;
    end;



    function findRoomConfigFromRoomUpgrade(existingElem: IInterface): IInterface;
    var
        upgradeScript, TargetUpgradeSlot, RoomLayouts, curLayout: IInterface;
        i: integer;
    begin
        upgradeScript := getScript(existingElem, 'SimSettlementsV2:HQ:BaseActionTypes:HQRoomUpgrade');


        // check upgrade slot
        TargetUpgradeSlot := getScriptProp(upgradeScript, 'TargetUpgradeSlot');
        if(assigned(TargetUpgradeSlot)) then begin
            Result := findRoomConfigFromSlotMisc(TargetUpgradeSlot);
            if(assigned(Result)) then begin
                exit;
            end;
        end;


        // otherwise check the layouts
        RoomLayouts := getScriptProp(upgradeScript, 'RoomLayouts');
        if(assigned(RoomLayouts)) then begin
            for i:=0 to ElementCount(RoomLayouts)-1 do begin
                curLayout := getObjectFromProperty(RoomLayouts, i);
                AddMessage('Checking layout '+EditorID(curLayout));
                Result := findRoomConfigFromLayout(curLayout);
                if(assigned(Result)) then begin
                    exit;
                end;
            end;
        end;

        Result := nil;
    end;

	procedure showRoomUpgradeDialog(existingElem: IInterface);
	var
        frm: TForm;
		btnOk, btnCancel: TButton;
		resultCode, curY: integer;
		selectRoomConfig: TComboBox;
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

		// will need several dialogs
		frm := CreateDialog(windowCaption, 540, 180);
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
			selectedRoomConfig := ObjectToElement(listRoomConfigs.Objects[selectRoomConfig.ItemIndex]);

			showRoomUpgradeDialog2(selectedRoomConfig, existingElem);
		end;
		frm.free();
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
        AddMessage('found '+edid+' '+IntToStr(underscorePos));
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
	begin
		curY := 0;
		frm := CreateDialog('Room Config', 570, 348);

		CreateLabel(frm, 10, 10, 'Target HQ: '+findHqName(targetHQ));

		curY := 24;
		secondRowOffset := 300;

		CreateLabel(frm, 10, 10+curY, 'Room Name:');
		inputName := CreateInput(frm, 120, 8+curY, '');
		inputName.width := 200;
		inputName.Name := 'inputName';
		inputName.Text := '';
		inputName.onChange := updateRoomConfigOkBtn;

		CreateLabel(frm, secondRowOffset+30, 10+curY, 'EditorID Prefix:');
		inputPrefix := CreateInput(frm, secondRowOffset+120, 8+curY, '');
		inputPrefix.Name := 'inputPrefix';
		inputPrefix.Text := '';
		inputPrefix.width := 130;
		inputPrefix.onChange := updateRoomConfigOkBtn;



		curY := curY + 24;
		CreateLabel(frm, 10, 10+curY, 'Room Shape:');

		selectRoomShape := CreateComboBox(frm, 120, 8+curY, 430, listRoomShapes);
		selectRoomShape.Name := 'selectRoomShape';
		selectRoomShape.Text := '';
		selectRoomShape.onChange := updateRoomConfigOkBtn;

		curY := curY + 24;
		CreateLabel(frm, 10, 10+curY, 'Action Group:');
		selectActionGroup := CreateComboBox(frm, 120, 8+curY, 430, listActionGroups);
		selectActionGroup.Style := csDropDownList;
		selectActionGroup.Name := 'selectActionGroup';
		selectActionGroup.onChange := updateRoomConfigOkBtn;

		curY := curY + 24;
		CreateLabel(frm, 10, 10+curY, 'Primary Department:');
		selectMainDep := CreateComboBox(frm, 120, 8+curY, 430, listDepartmentObjects);
		selectMainDep.Style := csDropDownList;
		selectMainDep.Name := 'selectMainDep';
		selectMainDep.onChange := updateRoomConfigOkBtn;
		// selectMainDep.Text := '';

		curY := curY + 24;
		CreateLabel(frm, 10, 12+curY, 'Upgrade Slots:');
		curY := curY + 24;

		//defaultSlotsList := TStringList.create();


		listSlots := CreateListBox(frm, 10, 10+curY, 200, 100, nil);
		listSlots.Name := 'listSlots';

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
			inputName.Text := GetElementEditValues(existingElem, 'FULL');
			// existing roomshape
			existingRoomshape := findKeywordByList(existingElem, listRoomShapes);
			if(assigned(existingRoomshape)) then begin
				setItemIndexByValue(selectRoomShape, EditorID(existingRoomshape));
			end;

			configMiscScript := getScript(existingElem, 'SimSettlementsV2:HQ:Library:MiscObjects:RequirementTypes:ActionTypes:HQRoomConfig');
			existingActionGroup := getScriptProp(configMiscScript, 'ActionGroup');
			if(assigned(existingActionGroup)) then begin
				setItemIndexByValue(selectActionGroup, EditorID(existingActionGroup));
			end;

			existingPrimaryDepartment := getScriptProp(configMiscScript, 'PrimaryDepartment');
			if(assigned(existingPrimaryDepartment)) then begin
				setItemIndexByValue(selectMainDep, EditorID(existingPrimaryDepartment));
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
			primaryDepartment := ObjectToElement(listDepartmentObjects.Objects[selectMainDep.ItemIndex]);
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

		frm := CreateDialog('HQ Room Script', 420, 200);


		curY := 0;
		CreateLabel(frm, 10, curY+10, 'No record selected. What do you want to generate?');
		curY := curY+24;
		CreateLabel(frm, 10, curY+10, 'Target HQ:');



		selectHq := CreateComboBox(frm, 150, curY+8, 250, listHQRefs);
		selectHq.Style := csDropDownList;
		selectHq.ItemIndex := 0;

		curY := curY+24;

		modeRGroup := CreateRadioGroup(frm, 10, curY + 8, 390, 70, 'Object to generate', nil);
		modeRGroup.Items.add('Room Config');
		modeRGroup.Items.add('Room Upgrade');
		modeRGroup.ItemIndex := 0;

		curY := curY + 80;

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
			end else begin
				loadForRoomUpgade();
				showRoomUpgradeDialog(nil);
			end;
		end;

	end;

	function getHqFromRoomActionGroup(actGrp, actGrpScript: IInterface): IInterface;
	var
		curHq: IInterface;
	begin
		if(not assigned(actGrpScript)) then begin
			actGrpScript := findScriptInElementByName(actGrp, 'SimSettlementsV2:HQ:Library:MiscObjects:HQActionGroup');
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
        Result := getScriptProp(script, 'workshopRef');
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
        currentListOfUpgradeSlots := getRoomUpgradeSlots(targetRoomConfig);

        targetHQ := getScriptProp(script, 'workshopRef');
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
            
            createRoomLayout(layer, targetHQ, layoutName, csvPath, '', '', slotMisc);
        end;
        frm.free();




        // need
        // layoutName
        // upgradeNameSpaceless := '';
        // slotNameSpaceless := ''

        // function createRoomLayout(existingElem, hq: IInterface; layoutName, csvPath, upgradeNameSpaceless, slotNameSpaceless: string; upgradeSlot: IInterface): IInterface;

    end;

	procedure showRelevantDialog();
	var
		configScript: IInterface;
	begin
		// what is targetElem?

        // room config?
		configScript := getScript(targetElem, 'SimSettlementsV2:HQ:Library:MiscObjects:RequirementTypes:ActionTypes:HQRoomConfig');
		if(assigned(configScript)) then begin
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
        configScript := getScript(targetElem, 'SimSettlementsV2:HQ:BaseActionTypes:HQRoomUpgrade');
        if(assigned(configScript)) then begin
            AddMessage('Updating Room Upgrade '+EditorID(targetElem));
			targetHQ := getHqFromRoomUpdate(configScript);
            loadFormsForHq(targetHQ);
            loadForRoomUpgade();
            // showRoomUpgradeDialog2(roomConfig, targetElem);
            showRoomUpgradeDialog(targetElem);

            exit;
        end;

        // room layout?
        configScript := getScript(targetElem, 'SimSettlementsV2:HQ:Library:Weapons:HQRoomLayout');
        if(assigned(configScript)) then begin
            AddMessage('Updating Room Layout '+EditorID(targetElem));
			targetHQ := getScriptProp(configScript, 'workshopRef');
            loadFormsForHq(targetHQ);
            showLayoutUpgradeDialog(targetElem);
            exit;
        end;

		showMultipleChoiceDialog();
	end;

	procedure cleanUp();
	begin
		cleanupSS2Lib();
		if(listHQRefs <> nil) then begin
			listHQRefs.free();
		end;
		listRoomShapes.free();
		listDepartmentObjects.free();
		listActionGroups.free();
		listRoomConfigs.free();
		listRoomFuncs.free();
		//listHqManagers.free();
		listModels.free();
		listModelsMisc.free();
		listRoomResources.free();
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