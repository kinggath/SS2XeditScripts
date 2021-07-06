{
    New script template, only shows processed records
    Assigning any nonzero value to Result will terminate script
}
unit ImportHqRoom;
	uses 'SS2\SS2Lib'; // uses praUtil

	var
		targetFile: IInterface;
		targetElem: IInterface;
		targetHQ: IInterface;
		// lists
		listHQRefs: TStringList;
		listRoomShapes: TStringList;
		listDepartmentObjects: TStringList;
		listActionGroups: TStringList;
		// general stuff needed from master
		SS2_HQ_FauxWorkshop: IInterface;
		SS2_FLID_HQActions: IInterface;
		SS2_HQ_WorkshopRef_GNN: IInterface;
		// templates
		SS2_HQGNN_Action_AssignRoomConfig_Template: IInterface;
		SS2_HQ_RoomSlot_Template_GNN: IInterface;
		SS2_HQ_RoomSlot_Template: IInterface;

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
		i: integer;
		hqName, edid: string;
	begin
		for i:=0 to ReferencedByCount(SS2_HQ_FauxWorkshop)-1 do begin
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

	procedure loadKeywordsFromFile(fromFile:  IInterface);
	var i: integer;
		curRec, group: IInterface;
		edid: string;
	begin
		group := GroupBySignature(fromFile, 'KYWD');
		for i:=0 to ElementCount(group)-1 do begin
			curRec := ElementByIndex(group, i);
			edid := EditorID(curRec);

			if(strStartsWith(edid, 'SS2_Tag_RoomShape')) then begin
				// AddMessage('Found RoomShape! '+EditorID(curRec));
				listRoomShapes.addObject(edid, curRec);
			end;
		end;
	end;

	procedure loadActivatorsFromFile(fromFile:  IInterface);
	var i: integer;
		curRec, group: IInterface;
		edid: string;
	begin
		group := GroupBySignature(fromFile, 'ACTI');
		for i:=0 to ElementCount(group)-1 do begin
			curRec := ElementByIndex(group, i);
			edid := EditorID(curRec);

			if(strStartsWith(edid, 'SS2_HQ_DepartmentObject_')) then begin
				// AddMessage('Found Department! '+EditorID(curRec));
				listDepartmentObjects.addObject(edid, curRec);
			end;
		end;
	end;

	procedure loadMiscsFromFile(fromFile:  IInterface);
	var i: integer;
		curRec, group, curHq: IInterface;
		edid: string;
	begin
		group := GroupBySignature(fromFile, 'MISC');
		for i:=0 to ElementCount(group)-1 do begin
			curRec := ElementByIndex(group, i);
			edid := EditorID(curRec);

			if(strStartsWith(edid, 'SS2_HQ_ActionGroup_')) then begin

				curHq := getHqFromRoomActionGroup(curRec);
				if(FormsEqual(curHq, targetHQ)) then begin
					listActionGroups.addObject(edid, curRec);
				end;
			end;
		end;
	end;

	procedure loadFormsFromFile(fromFile: IInterface);
	begin
		loadKeywordsFromFile(fromFile);
		loadActivatorsFromFile(fromFile);
		loadMiscsFromFile(fromFile);
	end;

	procedure loadForms();
	var
		i: integer;
		curFile: IInterface;
	begin
		AddMessage('Loading data for HQ '+findHqName(targetHQ)+'...');
		for i:=0 to MasterCount(targetFile)-1 do begin
			curFile := MasterByIndex(targetFile, i);
			loadFormsFromFile(curFile);
		end;
		loadFormsFromFile(targetFile);
		AddMessage('Data loaded.');
	end;

	function CreateListBox(frm: TForm; left: Integer; top: Integer; width: Integer; height: Integer; items: TStringList): TListBox;
	begin
		Result := TListBox.Create(frm);
        Result.Parent := frm;
        Result.Left := left;
        Result.Top := top;
        Result.Width := width;
        Result.Height := height;

        if(items <> nil) then begin
            Result.items := items;
        end;
	end;



    // Called before processing
    // You can remove it if script doesn't require initialization code
    function Initialize: integer;
    begin
        Result := 0;

		if(not initSS2Lib()) then begin
			Result := 1;
			exit;
		end;

		// records we always need
		SS2_HQ_FauxWorkshop := FindObjectByEdid('SS2_HQ_FauxWorkshop'); //SS2_HQ_FauxWorkshop "Workshop" [CONT:0400379B]
		SS2_FLID_HQActions := FindObjectByEdid('SS2_FLID_HQActions');
		SS2_HQGNN_Action_AssignRoomConfig_Template := FindObjectByEdid('SS2_HQGNN_Action_AssignRoomConfig_Template');
		SS2_HQ_RoomSlot_Template := FindObjectByEdid('SS2_HQ_RoomSlot_Template');
		SS2_HQ_RoomSlot_Template_GNN := FindObjectByEdid('SS2_HQ_RoomSlot_Template_GNN');
		if(not assigned(SS2_HQ_FauxWorkshop)) then begin
			AddMessage('no SS2_HQ_FauxWorkshop');
			Result := 1;
			exit;
		end;

		listHQRefs := TStringList.create;
		listRoomShapes := TStringList.create;
		listDepartmentObjects := TStringList.create;
		listActionGroups := TStringList.create;
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
		kwBase, curSlotName, configMiscEdid, roomNameSpaceless: string;
		oldRoomShapeKw, oldUpgradeMisc: IInterface;
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
		//setScriptProp(configMiscScript, 'RoomConfigKeyword', primaryDepartment); // generate
		setScriptProp(configMiscScript, 'RoomShapeKeyword', roomShapeKw);

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
		modeBox, selectHq: TComboBox;
		btnOk, btnCancel: TButton;
		resultCode, selectedIndex, selectedHQIndex, curY: integer;
	begin
		AddMessage('Loading HQs...');
		loadHQs();
		AddMessage('HQs Loaded.');

		frm := CreateDialog('HQ Room Script', 420, 180);


		curY := 0;
		CreateLabel(frm, 10, curY+10, 'No record selected. What do you want to generate?');
		curY := curY+24;
		CreateLabel(frm, 10, curY+10, 'Target HQ:');

		selectHq := CreateComboBox(frm, 150, curY+8, 250, listHQRefs);
		selectHq.Style := csDropDownList;
		selectHq.ItemIndex := 0;

		curY := curY+24;

		CreateLabel(frm, 10, curY+10, 'Object to generate:');

		modeBox := CreateComboBox(frm, 150, curY+8, 250, nil);
		modeBox.Items.add('Room Config');
		modeBox.Items.add('Room Upgrade');
		modeBox.ItemIndex := 0;
		modeBox.Style := csDropDownList;

		curY := curY + 60;

		btnOk := CreateButton(frm, 130, curY+4, 'OK');
		btnOk.ModalResult := mrYes;
		btnOk.Name := 'btnOk';
		btnOk.Default := true;

		btnCancel := CreateButton(frm, 210, curY+4, 'Cancel');
		btnCancel.ModalResult := mrCancel;

		btnOk.Width := 75;
		btnCancel.Width := 75;

		resultCode := frm.ShowModal();
		selectedIndex := modeBox.ItemIndex;
		selectedHQIndex := selectHq.ItemIndex;

		frm.free();

		if(resultCode = mrYes) then begin
			targetHQ := ObjectToElement(listHQRefs.Objects[selectedHQIndex]);
			loadForms();
			if(selectedIndex = 0) then begin
				showRoomConfigDialog(nil);
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