{
    Run on Room Config to update. Run on anything else to generate a new
}
unit ImportHqRoom;
	uses 'SS2\SS2Lib'; // uses praUtil

	const
		cacheFileModels = ProgramPath + 'Edit Scripts\SS2\AnimationMarkers.cache';
		progressBarChar = '|';
		progressBarLength = 70;
	var
		targetFile: IInterface;
		targetElem: IInterface;
		targetHQ: IInterface;
		// lists
		listHQRefs: TStringList;
		listRoomShapes: TStringList;
		listDepartmentObjects: TStringList;
		listActionGroups: TStringList;
		listRoomConfigs: TStringList;
		listRoomFuncs: TStringList;
		listHqManagers: TStringList;
		listModels: TStringList;
		listRoomResources: TStringList;
		// general stuff needed from master
		SS2_HQ_FauxWorkshop: IInterface;
		SS2_FLID_HQActions: IInterface;
		SS2_HQ_WorkshopRef_GNN: IInterface;
		WorkshopItemKeyword: IInterface;
		// templates
		SS2_HQGNN_Action_AssignRoomConfig_Template: IInterface;
		SS2_HQ_RoomSlot_Template_GNN: IInterface;
		SS2_HQ_RoomSlot_Template: IInterface;

		progressBarWindow: TForm;
		progressBarStack: TJsonArray;



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

		if(prevProgressData <> nil) then begin
			thisProgressData.F['size'] := prevProgressData.F['size'] / prevProgressData.F['max'];
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

			if(i < progressBarStack.count-1) then begin
				newNr := newNr + Round((progressData.I['cur'] / progressData.I['max']) * progressData.F['size']);
			end else begin
				newNr := newNr + Round(((cur) / progressData.I['max']) * progressData.F['size']);
				progressData.I['cur']  := cur;
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

	procedure loadModels();
	var
		containers, assets: TStringList;
		i, j: integer;
		curRes: string;
	begin

		if(FileExists(cacheFileModels)) then begin
			// load
			listModels.LoadFromFile(cacheFileModels);
			// removePrefixFromList('Meshes\AutoBuildPlots\Markers\Visible\Animation\', listModels);
		end else begin
			containers := TStringList.create();
			startProgress('Loading models...', containers.count-1);
			ResourceContainerList(containers);
			for i:=0 to containers.count-1 do begin
				assets := TStringList.create();

				ResourceList(containers[i], assets);
				for j:=0 to assets.count-1 do begin
					curRes := assets[j];

					if(strStartsWithCI(curRes, 'Meshes\AutoBuildPlots\Markers\Visible\Animation\')) then begin
						if(listModels.indexOf(curRes) < 0) then begin
							listModels.add(regexReplace(curRes, '^Meshes\\AutoBuildPlots\\Markers\\Visible\\Animation\\', ''));
						end;
					end;
				end;
				updateProgress(i);

				assets.free();
			end;

			endProgress();

			containers.free();
			listModels.saveToFile(cacheFileModels);
		end;
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
			listRoomResources.addObject(resName, curAv);
		end;
	end;


	procedure loadForRoomUpgade();
	begin
		loadResources();
		loadModels();
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

	procedure loadHQs();
	var
		curRef: IInterface;
		i, numRefs: integer;
		hqName, edid: string;
	begin
		numRefs := ReferencedByCount(SS2_HQ_FauxWorkshop)-1;
		for i:=0 to numRefs do begin
			curRef := ReferencedByIndex(SS2_HQ_FauxWorkshop, i);
			if (Signature(curRef) = 'REFR') and (FormsEqual(SS2_HQ_FauxWorkshop, pathLinksTo(curRef, 'NAME'))) then begin
				edid := EditorID(curRef);
				if(edid = 'SS2_HQ_WorkshopRef_GNN') then begin
					SS2_HQ_WorkshopRef_GNN := curRef;
				end;
				hqName := findHqName(curRef);
				// found one
				listHQRefs.addObject(hqName, curRef);
			end;
		end;
	end;

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

	procedure loadHqDepartments();
	var
		base, curRef, script, linkedTarget: IInterface;
		i: integer;
		departmentName: string;
	begin
		for i:=0 to ReferencedByCount(targetHQ)-1 do begin
			curRef := ReferencedByIndex(targetHQ, i);
			if (Signature(curRef) <> 'REFR') then begin
				continue;
			end;
			base := PathLinksTo(curRef, 'NAME');
			if (Signature(base) <> 'ACTI') then begin
				continue;
			end;

			linkedTarget := findLinkedRef(curRef, WorkshopItemKeyword);
			if (not FormsEqual(linkedTarget, targetHQ)) then begin
				continue;
			end;

			script := getScript(base, 'SimSettlementsV2:HQ:Library:ObjectRefs:DepartmentObject');
			if(assigned(script)) then begin
				// found!
				departmentName := GetElementEditValues(base, 'FULL');
				// AddMessage('Found '+FullPath(curRef));
				listDepartmentObjects.addObject(departmentName, curRef);
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

			if(strStartsWith(edid, 'SS2_Tag_RoomShape')) then begin
				// AddMessage('Found RoomShape! '+EditorID(curRec));
				listRoomShapes.addObject(edid, curRec);
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

			if(strStartsWith(edid, 'SS2_HQ_DepartmentObject_')) then begin
				// AddMessage('Found Department! '+EditorID(curRec));
				listDepartmentObjects.addObject(edid, curRec);
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

	procedure loadQuestsFromFile(fromFile:  IInterface);
	var i: integer;
		curRec, group, curScript: IInterface;
		edid: string;
	begin
		group := GroupBySignature(fromFile, 'QUST');
		startProgress('Loading quests from '+GetFileName(fromFile), ElementCount(group));
		for i:=0 to ElementCount(group)-1 do begin
			curRec := ElementByIndex(group, i);
			edid := EditorID(curRec);

			curScript := getScript(curRec, 'SimSettlementsV2:HQ:HQManagerQuest');
			// TODO figure out scripts which extend that

			if(assigned(curScript)) then begin
				// AddMessage('Found Department! '+EditorID(curRec));
				listHqManagers.addObject(edid, curRec);
			end;
			updateProgress(i);
		end;
		endProgress();
	end;

	procedure loadMiscsFromFile(fromFile:  IInterface);
	var i: integer;
		curRec, group, curHq, curScript: IInterface;
		edid, curName: string;
	begin
		group := GroupBySignature(fromFile, 'MISC');
		startProgress('Loading MISCs from '+GetFileName(fromFile), ElementCount(group));
		for i:=0 to ElementCount(group)-1 do begin
			
			curRec := ElementByIndex(group, i);
			edid := EditorID(curRec);

			if(strStartsWith(edid, 'SS2_HQ_ActionGroup_')) then begin
				curScript := getScript(curRec, 'SimSettlementsV2:HQ:Library:MiscObjects:HQActionGroup');
				if(assigned(curScript)) then begin

					curHq := getHqFromRoomActionGroup(curRec);
					if(FormsEqual(curHq, targetHQ)) then begin
						listActionGroups.addObject(edid, curRec);
					end;
				end;
				continue;
			end;

			if(pos('_Action_AssignRoomConfig_', edid) > 0) then begin
				curScript := getScript(curRec, 'SimSettlementsV2:HQ:Library:MiscObjects:RequirementTypes:ActionTypes:HQRoomConfig');
				if(assigned(curScript)) then begin
					// yes
					curName := getRoomConfigName(curRec);
					listRoomConfigs.addObject(curName, curRec);
				end;
				continue;
			end;

			if(strStartsWith(edid, 'SS2_HQRoomFunctionality_')) then begin
				curScript := getScript(curRec, 'SimSettlementsV2:HQ:Library:MiscObjects:HQRoomFunctionality');
				if(assigned(curScript)) then begin
					curName := GetElementEditValues(curRec, 'FULL');
					listRoomFuncs.addObject(curName, curRec);
				end;
				// SimSettlementsV2:HQ:Library:MiscObjects:HQRoomFunctionality
			end;


			if(strStartsWith(edid, 'SS2_HQResourceToken_WorkEnergy_')) then begin
				listRoomResources.addObject(GetElementEditValues(curRec, 'FULL'), curRec);
			end;
			updateProgress(i);
		end;
		endProgress();
	end;

	procedure loadFormsFromFile(fromFile: IInterface);
	begin
		startProgress('', 3);
		updateProgress(0);
		loadKeywordsFromFile(fromFile);
		// loadActivatorsFromFile(fromFile);
		updateProgress(1);
		loadMiscsFromFile(fromFile);
		updateProgress(2);
		loadQuestsFromFile(fromFile);
		endProgress();
	end;

	procedure loadForms();
	var
		i, numData: integer;
		curFile: IInterface;
	begin
		AddMessage('Loading data for HQ '+findHqName(targetHQ)+'...');
		numData := MasterCount(targetFile);
		startProgress('Loading data...', numData+1);
		for i:=0 to numData-1 do begin
			updateProgress(i);
			curFile := MasterByIndex(targetFile, i);
			loadFormsFromFile(curFile);
		end;
		updateProgress(numData);
		loadFormsFromFile(targetFile);
		loadHqDepartments();
		AddMessage('Data loaded.');
		endProgress();
	end;


    // Called before processing
    // You can remove it if script doesn't require initialization code
    function Initialize: integer;
    begin
		progressBarWindow := nil;
        Result := 0;

		if(not initSS2Lib()) then begin
			Result := 1;
			exit;
		end;

		// records we always need
		SS2_HQ_FauxWorkshop := FindObjectByEdid('SS2_HQ_FauxWorkshop'); //SS2_HQ_FauxWorkshop "Workshop" [CONT:0400379B]
		SS2_FLID_HQActions := FindObjectByEdid('SS2_FLID_HQActions');
		WorkshopItemKeyword := FindObjectByEdid('WorkshopItemKeyword');
		SS2_HQGNN_Action_AssignRoomConfig_Template := FindObjectByEdid('SS2_HQGNN_Action_AssignRoomConfig_Template');
		SS2_HQ_RoomSlot_Template := FindObjectByEdid('SS2_HQ_RoomSlot_Template');
		SS2_HQ_RoomSlot_Template_GNN := FindObjectByEdid('SS2_HQ_RoomSlot_Template_GNN');
		if(not assigned(SS2_HQ_FauxWorkshop)) then begin
			AddMessage('no SS2_HQ_FauxWorkshop');
			Result := 1;
			exit;
		end;

		progressBarStack := TJsonArray.create;

		listHQRefs := TStringList.create;
		listRoomShapes := TStringList.create;
		listDepartmentObjects := TStringList.create;
		listActionGroups := TStringList.create;
		listRoomFuncs := TStringList.create;
		listHqManagers := TStringList.create;
		listModels := TStringList.create;
		listRoomResources := TStringList.create;
		listRoomConfigs := TStringList.create;


		listRoomResources.Sorted := true;
		listModels.Sorted := true;
		listRoomConfigs.Sorted := true;
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
		inputName: TEdit;
		btnOk: TButton;
		selectMainDep, selectRoomShape, selectActionGroup: TComboBox;
		frm: TForm;
    begin
		frm := sender.parent;
        inputName := TEdit(frm.FindComponent('inputName'));
        selectMainDep := TComboBox(frm.FindComponent('selectMainDep'));
        selectRoomShape := TComboBox(frm.FindComponent('selectRoomShape'));
        selectActionGroup := TComboBox(frm.FindComponent('selectActionGroup'));

		btnOk := TButton(frm.FindComponent('btnOk'));

		if (trim(inputName.text) <> '') and (selectMainDep.ItemIndex >= 0) and (selectActionGroup.ItemIndex >= 0) and ((selectRoomShape.ItemIndex >= 0) or (trim(selectRoomShape.text) <> '')) then begin
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
			newString := StringReplace(trim(newString), ' ', '', [rfReplaceAll]);
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
		edidMisc := 'SS2_HQ_RoomSlot_'+roomShape+'_'+roomName+'_'+slotName;
		edidKw   := 'SS2_Tag_RoomSlot_'+roomShape+'_'+roomName+'_'+slotName;
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

		roomNameSpaceless := StringReplace(roomName, ' ', '', [rfReplaceAll]);

		if (assigned(roomShapeKw)) then begin
			roomShapeKwEdid := EditorID(roomShapeKw);
		end else begin
			// find/make KW
			roomShapeKw := getCopyOfTemplate(targetFile, keywordTemplate, roomShapeKwEdid);
		end;

		kwBase := stripPrefix('SS2_Tag_RoomShape_', roomShapeKwEdid);//regexExtract(roomShapeKwEdid, '_([^_]+)$', 1);
		if(kwBase = '') then begin
			kwBase := roomShapeKwEdid;
		end;

		if(not assigned(existingElem)) then begin
			configMiscEdid := 'SS2_HQ' + findHqNameShort(forHq)+'_Action_AssignRoomConfig_'+kwBase+'_'+roomNameSpaceless;
			configMisc := getCopyOfTemplate(targetFile, SS2_HQGNN_Action_AssignRoomConfig_Template, configMiscEdid);
			addKeywordByPath(configMisc, roomShapeKw, 'KWDA');

			roomConfigKeywordEdid := 'SS2_Tag_RoomConfig_'+kwBase+'_'+roomNameSpaceless;//<RoomShapeKeywordName>_<Name Entered Above>
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

		roomConfigKw := getCopyOfTemplate(targetFile, keywordTemplate, 'SS2_Tag_RoomConfig_'+kwBase+'_'+roomNameSpaceless);//SS2_Tag_RoomConfig_<RoomShapeKeywordName>_<Name Entered Above>

		setScriptProp(configMiscScript, 'RoomShapeKeyword', roomShapeKw);

		if(assigned(roomConfigKeyword)) then begin
			setScriptProp(configMiscScript, 'RoomConfigKeyword', roomConfigKeyword);
		end;

		roomUpgradeSlots := getOrCreateScriptProp(configMiscScript, 'RoomUpgradeSlots', 'Array of Object');
		clearProperty(roomUpgradeSlots);
		// RoomUpgradeSlots array of obj, generated from UpgradeSlots
		for i:=0 to UpgradeSlots.count-1 do begin
			curSlotName := StringReplace(UpgradeSlots[i], ' ', '', [rfReplaceAll]);

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

	function GetRoomSlotName(slotMisc: IInterface): string;
	var
		miscScript, slotKw: IInterface;
	begin
		Result := GetElementEditValues(slotMisc, 'FULL');
		if(Result <> '') then exit;

		miscScript := getScript(slotMisc, 'SimSettlementsV2:HQ:Library:MiscObjects:RequirementTypes:HQRoomUpgradeSlot_GNN');
		if(not assigned(miscScript)) then begin
			miscScript := getScript(slotMisc, 'SimSettlementsV2:HQ:Library:MiscObjects:RequirementTypes:HQRoomUpgradeSlot');
		end;

		slotKw := getScriptProp(miscScript, 'UpgradeSlotKeyword');
		Result := GetElementEditValues(slotMisc, 'FULL');
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

			Result.addObject(slotName, curSlot);
		end;

	end;

	function prependNoneEntry(list: TStringList): TStringList;
	var
		i: integer;
	begin
		Result := TStringList.create();
		Result.add('- NONE -');

		for i:=0 to list.count-1 do begin
			Result.addObject(list[i], list.Objects[i]);
		end;
	end;

	procedure addResourceToList(resIndex, cnt: Integer; box: TListBox);
	var
		nameBase: string;
		resForm: IInterface;
		resourceData: TJsonObject;
		i, newCnt: integer;
	begin
		if(cnt <= 0) then begin
			exit;
		end;

		nameBase := listRoomResources[resIndex];
		resForm := listRoomResources.Objects[resIndex];

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
	begin
		inputPath := TEdit(sender.parent.FindComponent('inputPath'));
		inputName := TEdit(sender.parent.FindComponent('inputName'));
		btnOk := TButton(sender.parent.FindComponent('btnOk'));

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

	function getLayoutDisplayName(layoutName: string; layoutPath: string): string;
	begin
		Result := layoutName + ': ' + ExtractFileName(layoutPath);
	end;

	procedure addOrEditLayout(layoutsBox: TListBox; index: integer);
	var
        frm: TForm;
		btnOk, btnCancel, btnBrowse: TButton;
		inputName, inputPath: TEdit;
		title, layoutName, layoutPath, layoutDisplayName: string;
		resultCode: integer;
		layoutData: TJsonObject;
	begin
		if(index < 0) then begin
			title := 'Add Room Layout';
		end else begin
			title := 'Edit Room Layout';
		end;
		frm := CreateDialog(title, 400, 160);

		CreateLabel(frm, 10, 10, 'Layout Name:');
		inputName := CreateInput(frm, 130, 8, '');
		inputName.Name := 'inputName';
		inputName.Text := '';
		inputName.onchange := layoutBrowseUpdateOk;

		CreateLabel(frm, 10, 34, 'Layout Spawns File:');
		inputPath := CreateInput(frm, 10, 54, '');
		inputPath.Width := 320;
		inputPath.Name := 'inputPath';
		inputPath.Text := '';
		inputPath.onchange := layoutBrowseUpdateOk;

		btnBrowse := CreateButton(frm, 340, 52, '...');
		btnBrowse.onclick := layoutBrowseHandler;

		btnOk := CreateButton(frm, 100, 84, 'OK');
		btnOk.ModalResult := mrYes;
		btnOk.Name := 'btnOk';
		btnOk.Default := true;

		btnCancel := CreateButton(frm, 200, 84, 'Cancel');
		btnCancel.ModalResult := mrCancel;

		btnOk.Width := 75;
		btnCancel.Width := 75;

		if(index >= 0) then begin
			layoutData := layoutsBox.Items.Objects[index];
			inputName.Text := layoutData.S['name'];
			inputPath.Text := layoutData.S['path'];
		end;

		layoutBrowseUpdateOk(btnOk);

		resultCode := frm.showModal();
		if(resultCode = mrYes) then begin
				layoutName := trim(inputName.Text);
				layoutPath := trim(inputPath.Text);
				layoutDisplayName := getLayoutDisplayName(layoutName, layoutPath);
			if(index < 0) then begin
				layoutData := TJsonObject.create();
				layoutData.S['name'] := layoutName;
				layoutData.S['path'] := layoutPath;

				layoutsBox.Items.addObject(layoutDisplayName, layoutData);
			end else begin
				layoutData := layoutsBox.Items.Objects[index];
				layoutData.S['name'] := layoutName;
				layoutData.S['path'] := layoutPath;
				layoutsBox.Items[index] := layoutDisplayName;
			end;
		end;

		frm.free();
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
	end;

	procedure showRoomUpgradeDialog2(targetRoomConfig, existingElem: IInterface);
	var
        frm: TForm;
		btnOk, btnCancel: TButton;
		resultCode, curY: integer;
		roomSlots: TStringList;
		selectUpgradeSlot, selectDepartment, selectModel, selectHqManager: TComboBox;
		assignDepAtEnd, assignDepAtStart, disableClutter, disableGarbarge, defaultConstMarkers, realTimeTimer: TCheckBox;
		departmentList, modelList: TStringList;
		inputName, inputDuration: TEdit; ///Duration: Float - default to 24

		resourceGroup: TGroupBox;
		resourceBox: TListBox;
		resourceAddBtn, resourceRemBtn, resourceEdtBtn: TButton;

		roomFuncsGroup: TGroupBox;
		roomFuncsBox: TListBox;
		roomFuncAddBtn, roomFuncRemBtn: TButton;

		layoutsGroup: TGroupBox;
		layoutsBox: TListBox;
		layoutsAddBtn, layoutsRemBtn, layoutsEdtBtn: TButton;
	begin
		// load the slots for what we have
		if(assigned(targetRoomConfig)) then begin
			roomSlots := getRoomUpgradeSlots(targetRoomConfig);
		end;

		frm := CreateDialog('Generating Room Upgrade', 590, 540);
		curY := 0;
		if(not assigned(existingElem)) then begin
			CreateLabel(frm, 10, 10+curY, 'HQ: '+EditorID(targetHQ)+'.');
			CreateLabel(frm, 10, 28+curY, 'Room Shape: '+EditorID(targetRoomConfig));
		end;
		curY := curY + 42;
		CreateLabel(frm, 10, 10+curY, 'Name:');
		inputName := CreateInput(frm, 150, 8+curY, '');
		inputName.width := 200;

		curY := curY + 28;
		CreateLabel(frm, 10, 10+curY, 'Model:');

		modelList := prependNoneEntry(listModels);
		selectModel := CreateComboBox(frm, 150, 8+curY, 200, modelList);
		selectModel.Style := csDropDownList;
		selectModel.Name := 'selectModel';

		curY := curY + 28;
		CreateLabel(frm, 10, 10+curY, 'Upgrade slot: ');
		selectUpgradeSlot := CreateComboBox(frm, 150, 8+curY, 200, roomSlots);
		selectUpgradeSlot.Style := csDropDownList;
		selectUpgradeSlot.Name := 'selectUpgradeSlot';
		// selectUpgradeSlot.onChange := updateRoomUpgrade1OkBtn;
		curY := curY + 42;
		assignDepAtStart := CreateCheckbox(frm, 10, curY, 'Assign department to room at start');
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
		layoutsBox := CreateListBox(layoutsGroup, 8, 16, 490, 72, nil);
		layoutsBox.Name := 'layoutsBox';

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

		curY := curY + 110;

		//curY := curY + 136;
		btnOk := CreateButton(frm, 220, curY, 'OK');
		btnOk.ModalResult := mrYes;
		btnOk.Name := 'btnOk';
		btnOk.Default := true;

		btnCancel := CreateButton(frm, 295	, curY, 'Cancel');
		btnCancel.ModalResult := mrCancel;

		btnOk.Width := 75;
		btnCancel.Width := 75;

		resultCode := frm.ShowModal();
		if(resultCode = mrYes) then begin

		end;


		// cleanup objects?
		freeStringListObjects(resourceBox.Items);
		freeStringListObjects(layoutsBox.Items);

		roomSlots.free();
		modelList.free();
		departmentList.free();
		frm.free();
	end;

	procedure showRoomUpgradeDialog(existingElem: IInterface);
	var
        frm: TForm;
		btnOk, btnCancel: TButton;
		resultCode, curY: integer;
		selectRoomConfig: TComboBox;
		selectedRoomConfig: IInterface;
	begin
		// will need several dialogs
		frm := CreateDialog('Generating Room Upgrade', 540, 180);
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

	procedure showRoomConfigDialog(existingElem: IInterface);
	var
        frm: TForm;
		selectRoomShape, selectMainDep, selectActionGroup: TComboBox;
		curY, resultCode: integer;
		inputName: TEdit;
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

		CreateLabel(frm, 10, 10+curY, 'Room Name:');
		inputName := CreateInput(frm, 150, 8+curY, '');
		inputName.width := 200;
		inputName.Name := 'inputName';
		inputName.Text := '';
		inputName.onChange := updateRoomConfigOkBtn;

		curY := curY + 24;
		CreateLabel(frm, 10, 10+curY, 'Room Shape:');

		selectRoomShape := CreateComboBox(frm, 150, 8+curY, 400, listRoomShapes);
		selectRoomShape.Name := 'selectRoomShape';
		selectRoomShape.Text := '';
		selectRoomShape.onChange := updateRoomConfigOkBtn;

		curY := curY + 24;
		CreateLabel(frm, 10, 10+curY, 'Action Group:');
		selectActionGroup := CreateComboBox(frm, 150, 8+curY, 400, listActionGroups);
		selectActionGroup.Style := csDropDownList;
		selectActionGroup.Name := 'selectActionGroup';
		selectActionGroup.onChange := updateRoomConfigOkBtn;

		curY := curY + 24;
		CreateLabel(frm, 10, 10+curY, 'Primary Department:');
		selectMainDep := CreateComboBox(frm, 150, 8+curY, 400, listDepartmentObjects);
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
		end;

		updateRoomConfigOkBtn(btnCancel);

		resultCode := frm.ShowModal();
		if(resultCode = mrYes) then begin
			// do stuff
			roomName := trim(inputName.Text);
			roomShapeKw := nil;
			roomShapeKwEdid := StringReplace(selectRoomShape.Text, ' ', '', [rfReplaceAll]);
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
		AddMessage('Loading HQs...');
		loadHQs();
		AddMessage('HQs Loaded.');

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
			loadForms();
			if(selectedIndex = 0) then begin
				showRoomConfigDialog(nil);
			end else begin
				loadForRoomUpgade();
				showRoomUpgradeDialog(nil);
			end;
		end;
	end;

	function getHqFromRoomActionGroup(actGrp: IInterface): IInterface;
	var
		actGrpScript, curHq: IInterface;
	begin
		actGrpScript := getScript(actGrp, 'SimSettlementsV2:HQ:Library:MiscObjects:HQActionGroup');

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

		Result := getHqFromRoomActionGroup(actGrp);
	end;

	procedure showRelevantDialog();
	var
		configScript: IInterface;
	begin
		// what is targetElem?
		configScript := getScript(targetElem, 'SimSettlementsV2:HQ:Library:MiscObjects:RequirementTypes:ActionTypes:HQRoomConfig');
		if(assigned(configScript)) then begin
			AddMessage('Updating '+EditorID(targetElem));
			loadHQs();
			targetHQ := getHqFromRoomConfig(configScript);
			loadForms();
			showRoomConfigDialog(targetElem);
			// a room config
			exit;
		end;

		showMultipleChoiceDialog();
	end;

	procedure cleanUp();
	begin
		cleanupSS2Lib();
		listHQRefs.free();
		listRoomShapes.free();
		listDepartmentObjects.free();
		listActionGroups.free();
		listRoomConfigs.free();
		listRoomFuncs.free();
		listHqManagers.free();
		listModels.free();
		listRoomResources.free();

		progressBarStack.free();
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

		showRelevantDialog();

        Result := 0;

		cleanUp();
    end;

end.