{
    Run on room
    SS2C2_HQGNN_Action_RoomConstruction_GNN512Box_EntranceRight_ArmorLab "Armor Lab" [MISC:04028627]
}
unit ChangeRoomConfig;
    uses 'SS2\SS2Lib'; // uses praUtil
	uses 'SS2\PexParser';

    var
        SS2_HQ_WorkshopRef_GNN: IInterface;
        targetFile: IInterface;

    // Called before processing
    // You can remove it if script doesn't require initialization code
    function Initialize: integer;
    begin
        Result := 0;
        if(not initSS2Lib()) then begin
			Result := 1;
			exit;
		end;

        SS2_HQ_WorkshopRef_GNN := getFormByFilenameAndFormID('SS2_XPAC_CHapter2.esm', $0001A118);
        if(not assigned(SS2_HQ_WorkshopRef_GNN)) then begin
            AddMessage('Failed to find SS2_HQ_WorkshopRef_GNN');
			Result := 1;
            exit;
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

    function getHqFromRoomUpdate(configScript: IInterface): IInterface;
	var
		actGrp, actGrpScript, curHq: IInterface;
	begin
		actGrp := getScriptProp(configScript, 'DepartmentHQActionGroup');

		Result := getHqFromRoomActionGroup(actGrp, nil);
	end;

    function showTargetConfigSelection(curHq, curMisc, curMiscScript, curConfig: IInterface): IInterface;
    var
        possibleConfigs: TStringList;
        frm: TForm;
		btnOk, btnCancel: TButton;
		resultCode, curY: integer;
		selectRoomConfig: TComboBox;
    begin
        Result := nil;
        possibleConfigs := loadRoomConfigs(curHq);

        frm := CreateDialog('Change Room Config', 540, 280);
        curY := 10;
        CreateLabel(frm, 10, curY, 'HQ: '+EditorID(curHq)+'.');
        curY := curY + 18;
        CreateLabel(frm, 10, curY, 'Room: '+EditorID(curMisc)+'.');
        curY := curY + 18;
		CreateLabel(frm, 10, curY, 'Current Room Config: '+getRoomConfigName(curConfig));
        curY := curY + 28;
		CreateLabel(frm, 10, curY, 'New Room Config:');
        curY := curY + 18;

        selectRoomConfig := CreateComboBox(frm, 10, curY, 500, possibleConfigs);
		selectRoomConfig.Style := csDropDownList;
		selectRoomConfig.Name := 'selectRoomConfig';
		// selectRoomConfig.onChange := updateRoomUpgrade1OkBtn;

        curY := curY + 64;
		btnOk := CreateButton(frm, 200, curY, 'Next');
		btnOk.ModalResult := mrYes;
		btnOk.Name := 'btnOk';
		btnOk.Default := true;

		btnCancel := CreateButton(frm, 275	, curY, 'Cancel');
		btnCancel.ModalResult := mrCancel;

        resultCode := frm.ShowModal();

		if(resultCode = mrYes) then begin
            if(selectRoomConfig.ItemIndex >= 0) then begin
                Result := ObjectToElement(selectRoomConfig.Items.Objects[selectRoomConfig.ItemIndex]);
            end;
        end;

        frm.free();

        possibleConfigs.free();
    end;

    function showSlotSelection(room, oldConfigScript, newConfigScript: IInterface): TJsonObject;
    var
        newSlots: TStringList;
        curSlotsNew, curSlotsOld, curSlotScript, curSlotKw, newSlotMisc, oldSlotKw, oldSlotMisc: IInterface;
        frm: TForm;
		btnOk, btnCancel: TButton;
		resultCode, curY: integer;
		selectSlotConfig: TComboBox;
        newSlotIndex, curIndex, i: integer;
        oldSlotName, elemName, oldKey, newKey: string;
    begin
        Result := nil;
        newSlots := TStringList.create;
        curSlotsNew := getScriptProp(newConfigScript, 'RoomUpgradeSlots');
		for i:=0 to ElementCount(curSlotsNew)-1 do begin
            // this is a MISC
            newSlotMisc := getObjectFromProperty(curSlotsNew, i);
            //curSlotKw := findSlotKeywordFromSlotMisc(curSlot);
            //AddMessage('Slot what '+EditorID(curSlotKw)+' '+DisplayName(curSlotKw));
			newSlots.addObject(GetRoomSlotName(newSlotMisc), newSlotMisc);

            //newSlotIndex
            {if(oldSlotName = GetRoomSlotName(curSlot)) then begin
                newSlotIndex := curIndex;
            end;}
        end;
        
        frm := CreateDialog('Change Room Config', 540, 200);
        curY := 10;
        //CreateLabel(frm, 10, curY, 'HQ: '+EditorID(curHq)+'.');
        // curY := curY + 18;
        CreateLabel(frm, 10, curY, 'Room: '+EditorID(room)+'.');
        curY := curY + 18;
		

        curSlotsOld := getScriptProp(oldConfigScript, 'RoomUpgradeSlots');
		for i:=0 to ElementCount(curSlotsOld)-1 do begin
            // this is a MISC
            oldSlotMisc := getObjectFromProperty(curSlotsOld, i);
            oldSlotName := GetRoomSlotName(oldSlotMisc);
            //oldSlotKw := findSlotKeywordFromSlotMisc(oldSlotMisc);
            //if(hasKeywordByPath(room, oldSlotKw, 'KWDA')) then begin
            //    break;
            //end;
            CreateLabel(frm, 10, curY+2, 'Current Slot: '+GetRoomSlotName(oldSlotMisc));
            CreateLabel(frm, 200, curY+2, 'New Slot:');

            elemName := 'newSlotFor_'+EditorID(oldSlotMisc);

            selectSlotConfig := CreateComboBox(frm, 250, curY, 200, newSlots);
            selectSlotConfig.Style := csDropDownList;
            selectSlotConfig.Name := elemName;
            selectSlotConfig.ItemIndex := newSlots.IndexOf(oldSlotName);
            if(selectSlotConfig.ItemIndex < 0) then begin
                selectSlotConfig.ItemIndex = 0;
            end;
            curY := curY + 28;
            // selectRoomConfig.onChange := updateRoomUpgrade1OkBtn;
        end;

       

        curY := curY + 24;
		btnOk := CreateButton(frm, 200, curY, 'Next');
		btnOk.ModalResult := mrYes;
		btnOk.Name := 'btnOk';
		btnOk.Default := true;

		btnCancel := CreateButton(frm, 275	, curY, 'Cancel');
		btnCancel.ModalResult := mrCancel;


        frm.Height := curY + 60;
        resultCode := frm.ShowModal();
		if(resultCode = mrYes) then begin
            Result := TJsonObject.create;
            for i:=0 to ElementCount(curSlotsOld)-1 do begin
                oldSlotMisc := getObjectFromProperty(curSlotsOld, i);
                newSlotMisc := nil;
                elemName := 'newSlotFor_'+EditorID(oldSlotMisc);
                selectSlotConfig := TComboBox(frm.FindComponent(elemName));
                if(selectSlotConfig.ItemIndex >= 0) then begin
                    newSlotMisc := ObjectToElement(selectSlotConfig.Items.Objects[selectSlotConfig.ItemIndex]);
                    oldKey := FormToStr(oldSlotMisc);
                    newKey := FormToStr(newSlotMisc);
                    Result.S[oldKey] := newKey;
                end;
            end;
        end;
        frm.free();

        newSlots.free();
    end;

    procedure processRoomUpgrade(e, script: IInterface);
    var
        selectedRoomConfig, curHq, RoomLayouts, layout, newConfig: IInterface;
        actisAndCobis: TJsonObject;
        i: integer;
        oldConfigScript, newConfigScript: IInterface;
        oldShapeKw, newShapeKw: IInterface;
        oldRoomSlot, newRoomSlot, curSlots, oldSlotMisc, oldSlotKw, oldTagKw, layoutScript: IInterface;
        slotMapping: TJsonObject;
        oldSlotKey: string;
    begin
        // find the stuff
        selectedRoomConfig := findRoomConfigFromRoomUpgrade(e);
        curHq := getHqFromRoomUpdate(script);
        AddMessage('thing itself='+EditorID(e));
        AddMessage('config='+EditorID(selectedRoomConfig));
        AddMessage('curHq='+EditorID(curHq));

        newConfig := showTargetConfigSelection(curHq, e, script, selectedRoomConfig);

        if(not assigned(newConfig)) then begin
            AddMessage('Nothing selected');
            exit;
        end;

        if(IsSameForm(selectedRoomConfig, newConfig)) then begin
            AddMessage('Config not changed');
            exit;
        end;

        oldConfigScript := getScript(selectedRoomConfig, 'simsettlementsv2:hq:library:miscobjects:requirementtypes:actiontypes:hqroomconfig');
        newConfigScript := getScript(newConfig, 'simsettlementsv2:hq:library:miscobjects:requirementtypes:actiontypes:hqroomconfig');

        


        slotMapping := showSlotSelection(e, oldConfigScript, newConfigScript);
        if(slotMapping = nil) then begin
            AddMessage('Cancelled slot mapping');
            exit;
        end;
        
        // newSlotKw := findSlotKeywordFromSlotMisc(newRoomSlot);



        // 1. Change the RoomSlot keyword that's on the Action form. For this, you'd first remove all of the RoomSlot keywords found on the old config, and then you'll want to present a dropdown, asking the player to choose which slot misc object from the new config to use, and just default the drop down to being on the one with Base in the EDID, which will cover 90% of use cases, and pull the keyword from that slot.
        curSlots := getScriptProp(oldConfigScript, 'RoomUpgradeSlots');
		for i:=0 to ElementCount(curSlots)-1 do begin
            // this is a MISC
            oldSlotMisc := getObjectFromProperty(curSlots, i);
            oldSlotKw := findSlotKeywordFromSlotMisc(oldSlotMisc);
            oldSlotKey := FormToStr(oldSlotMisc);
            removeKeywordByPath(e, oldSlotKw, 'KWDA');
        end;
        newRoomSlot := StrToForm(slotMapping.S[oldSlotKey]);
        ensureKeywordByPath(e, findSlotKeywordFromSlotMisc(newRoomSlot), 'KWDA');
        // 2. Change the TargetUpgradeSlot script property, to the slot selected in step 2.
        setScriptProp(script, 'TargetUpgradeSlot', newRoomSlot);

        // find layouts
        RoomLayouts := getScriptProp(script, 'RoomLayouts');

        for i:=0 to ElementCount(RoomLayouts)-1 do begin
            // 1. Change the TagKeyword script property on all the layouts to match the corresponding new ones, you'll have to use EDID matching, looking for the "Base", "Decorations", "Lighting", etc portion.
            layout := getObjectFromProperty(RoomLayouts, i);
            layout := getOrCreateElementOverride(layout, targetFile);
            AddMessage('layout='+EditorID(layout));
            layoutScript := getScript(layout, 'SimSettlementsV2:HQ:Library:Weapons:HQRoomLayout');
            oldTagKw := getScriptProp(layoutScript, 'TagKeyword');
            oldSlotMisc := findSlotMiscFromKeyword(oldTagKw);
            oldSlotKey := FormToStr(oldSlotMisc);
            newRoomSlot := StrToForm(slotMapping.S[oldSlotKey]);
            setScriptProp(layoutScript, 'TagKeyword', newRoomSlot);
        end;
        slotMapping.free();
        
        oldShapeKw := getScriptProp(oldConfigScript, 'RoomShapeKeyword');
        newShapeKw := getScriptProp(newConfigScript, 'RoomShapeKeyword');
        // if room shape changed, do the other stuff

        {
        on e:
        If the room shape keyword is different, you'll also need to:
        1. Change the RoomShape keyword that's on the Action form to the one from the new config.
        2. Change the RoomRequiredKeywords script property, it will have the old config's room shape as one of the entries, which will need to be changed to the new config's room shape.
        3. Change the portion of the EDID with the room shape to match the new room shape.
        }

        {
        on layouts:

        If the room shape keyword is different:
        1. Change the portion of the EDID with the room shape to match the new one.
        }

        actisAndCobis := findRoomUpgradeActivatorsAndCobjs(e);
        AddMessage(actisAndCobis.toString());
        {
        Looks like the RoomShape is also used in the EDIDs for the Activator and COBJ records as well, so basically if the RoomShape keyword is different, need to go update all the EDIDs.
        }
        actisAndCobis.free();
    end;

    function getHqForRoomConfig(e: IInterface): IInterface;
	var
		i: integer;
		curScript, primaryDepartment, linkedRefs, curKw, curRef, linkedEntry: IInterface;
		RoomUpgradeSlots, curSlot, curSlotScript, HQLocation: IInterface;
	begin
		//AddMessage('Searching HQ for '+EditorID(e));
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

    procedure loadRoomConfig(curFileName: string; roomConfig, roomConfigScript, forHq: IInterface; list: TStringList);
    var
        curName, curHqKey, slotName, slotHexId, existingSlotHexId: string;
        curFormID: cardinal;
        curHq, RoomUpgradeSlots, curSlot: IInterface;
        slotJson: TJsonObject;
        i: integer;
    begin
        curName := getRoomConfigName(roomConfig);

        curFormID := getElementLocalFormId(roomConfig);
        curHq := getHqForRoomConfig(roomConfig);
        if(not isSameForm(curHq, forHq)) then exit;
        //curHqKey := FormToAbsStr(curHq);

        if(EditorID(roomConfig) = 'SS2C2_HQGNN_Action_AssignRoomConfig_Template') then exit;

        // currentCacheFile.O['files'].O[curFileName].O['HQData'].O[curHqKey].O['RoomConfigs'].S[curName] := IntToHex(curFormID, 8);
        //AddMessage('Found this config: '+EditorID(roomConfig));
        list.addObject(getRoomConfigName(roomConfig), roomConfig);
        {
        // also slots
        RoomUpgradeSlots := getScriptProp(roomConfigScript, 'RoomUpgradeSlots');

        //slotJson := currentCacheFile.O['files'].O[curFileName].O['HQData'].O[curHqKey].O['RoomConfigSlots'];
		for i:=0 to ElementCount(RoomUpgradeSlots)-1 do begin
			curSlot := getObjectFromProperty(RoomUpgradeSlots, i);

            addRoomConfigSlot(curFileName, curHqKey, roomConfig, curSlot);
		end;
        }
    end;

    procedure loadMiscsFromFile(fromFile, forHq: IInterface; list: TStringList);
	var i: integer;
		curRec, group, curHq, curScript: IInterface;
		edid, curName, curFileName, curHqKey: string;
		curFormID: cardinal;
	begin
		curFileName := GetFileName(fromFile);
		group := GroupBySignature(fromFile, 'MISC');
		// startProgress('Loading MISCs from '+GetFileName(fromFile), ElementCount(group));
		for i:=0 to ElementCount(group)-1 do begin

			curRec := ElementByIndex(group, i);
			edid := EditorID(curRec);

			//updateProgress(i);

			if(pos('_Action_AssignRoomConfig_', edid) > 0) then begin
                // room config
				curScript := getScript(curRec, 'SimSettlementsV2:HQ:Library:MiscObjects:RequirementTypes:ActionTypes:HQRoomConfig');
				if(assigned(curScript)) then begin
                    loadRoomConfig(curFileName, curRec, curScript, forHq, list);
				end;
				continue;
			end;
        end;
    end;

    function loadRoomConfigs(forHq: IInterface): TStringList;
    var
        masterList: TStringList;
        i: integer;
        curFileName: string;
    begin
        Result := TStringList.create;
        masterList := getMasterList(targetFile);

        for i:=0 to masterList.count-1 do begin
            AddMessage('Checking '+masterList[i]);
            // curFileName := filesToReload.S[i];
            loadMiscsFromFile(ObjectToElement(masterList.Objects[i]), forHq, Result);
        end;
        loadMiscsFromFile(targetFile, forHq, Result);

        masterList.free();
    end;

    // called for every record selected in xEdit
    function Process(e: IInterface): integer;
    var
        script: IInterface;
    begin
        Result := 0;

        script := getScript(e, 'simsettlementsv2:hq:baseactiontypes:hqroomupgrade');
        if(not assigned(script)) then exit;

        // comment this out if you don't want those messages
        AddMessage('Processing: ' + FullPath(e));
        targetFile := GetFile(e);

        processRoomUpgrade(e, script);

    end;

    procedure cleanUp();
	begin
		cleanupSS2Lib();
        pexCleanUp();
    end;

    // Called after processing
    // You can remove it if script doesn't require finalization code
    function Finalize: integer;
    begin
        cleanUp();
        Result := 0;
    end;

end.