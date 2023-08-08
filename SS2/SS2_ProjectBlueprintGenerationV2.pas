{
 Adds items to formlists, creates COBJs, and renames objects
}
unit UserScript;

uses dubhFunctions; // dubhFunctions uses mteFunctions
uses praUtil;

var
  slImported, slRow: TStringList;
  importFilePath, sPrefix: string;
  doScriptsOnly, doImport, doStop: boolean;
  debug: boolean;
  FormRecord, MyFormRecord: IInterface;
    
//=========================================================================
// OptionsForm: Provides user with options for merging
procedure OptionsForm;
var
  sf: TMemIniFile;
  frm: TForm;
  btnOk, btnCancel: TButton;
  lb1, lb2: TLabel;
  ed1, ed2: TEdit;
  pnl: TPanel;
  sb: TScrollBox;
  i, j, k, height, m, more: integer;
  holder: TObject;
  masters, e, f: IInterface;
  s: string;
  doCloseSF: boolean;
begin
	more := 0;
	frm := TForm.Create(nil);
	frm.Caption := 'Add Items To Project Blueprint V2';

	frm.Width := Screen.Width / 3 * 2;
	frm.Position := poScreenCenter;
	height := 240;
	if height > (Screen.Height - 100) then begin
	frm.Height := Screen.Height - 100;
	sb := TScrollBox.Create(frm);
	sb.Parent := frm;
	sb.Height := Screen.Height - 290;
	sb.Align := alTop;
	holder := sb;
	end
	else begin
	frm.Height := height;
	holder := frm;
	end;

	pnl := TPanel.Create(frm);
	pnl.Parent := frm;
	pnl.BevelOuter := bvNone;
	pnl.Align := alBottom;
	pnl.Height := 190;

	lb1 := TLabel.Create(frm);
	lb1.Parent := pnl;
	lb1.Left := 26;
	lb1.Top := 18;
	lb1.Caption := 'File Path';
	lb1.Width := 90;

	ed1 := TEdit.Create(frm);
	ed1.Parent := pnl;
	ed1.Left := lb1.Left + lb1.width;
	ed1.Top := lb1.top;
	ed1.Width := frm.Width - lb1.Width - 60;
	ed1.Text := '';
	
	
	lb2 := TLabel.Create(frm);
	lb2.Parent := pnl;
	lb2.Left := 26;
	lb2.Top := 48;
	lb2.Caption := 'New Static Prefix';
	lb2.Width := 90;
	
	ed2 := TEdit.Create(frm);
	ed2.Parent := pnl;
	ed2.Left := lb1.Left + lb2.width;
	ed2.Top := lb2.top;
	ed2.Width := frm.Width - lb2.Width - 60;
	ed2.Text := '';

	btnOk := TButton.Create(frm);
	btnOk.Parent := pnl;
	btnOk.Caption := 'OK';
	btnOk.ModalResult := mrOk;
	btnOk.Left := 60;
	btnOk.Top := pnl.Height - 40;

	btnCancel := TButton.Create(frm);
	btnCancel.Parent := pnl;
	btnCancel.Caption := 'Cancel';
	btnCancel.ModalResult := mrCancel;
	btnCancel.Left := btnOk.Left + btnOk.Width + 16;
	btnCancel.Top := btnOk.Top;

	frm.ActiveControl := btnOk;
      
	if frm.ShowModal = mrOk then begin
		importFilePath := ed1.Text;
		sPrefix := DeleteSpaces(ed2.Text);
		
		if(Length(sPrefix) = 0) then begin
			AddMessage('You must enter a prefix for your object copies.');
			doStop := True;
		end;
	end else
		doStop := True;
    
	frm.Free;
end;

function GetRecordFromEditorID(file: IInterface; editorID: string): IInterface;
var
	i, j, k: integer;
	g, thisFile: IInterface;
begin
	// if file found, load groups
    if Assigned(file) then begin
      for i := 0 to ElementCount(file) - 1 do begin
		g := ElementByIndex(file, i);
		if Signature(g) = 'TES4' then Continue;
		
		Result := MainRecordByEditorID(g, editorID);
		
		if(Result <> Nil) then begin
			Break;
		end;
      end;
	  
		if(Result <> Nil) then begin
			//Checking = Nil fails
		end else begin
			// Check the loaded files
			for i := 0 to FileCount - 1 do begin
				thisFile := FileByIndex(i);
				
				if Assigned(thisFile) then begin
					for j := 0 to ElementCount(thisFile) - 1 do begin
						g := ElementByIndex(thisFile, j);
						if Signature(g) = 'TES4' then Continue;
						
						Result := MainRecordByEditorID(g, editorID);
						
						if(Result <> Nil) then begin
							Exit;
						end;
					end;
				end;
				
				if(Result <> Nil) then begin
					Break;
				end;
			end;
			
			if(Result <> Nil) then begin
				//Checking = Nil fails
			end else begin
				//AddMessage('Could not find ' + editorID + ' in file ' + GetFileName(file));
			end;
		end;
    end;
end;


function GetRecordFromFormID(file: IInterface; formID: string): IInterface;
var
	sTemp: string;
	i: integer;
	g, master: IInterface;
begin
	// if file found, load groups
    if Assigned(file) then begin
		if(Length(formID) < 8) then begin
			try
				sTemp := IntToHex(StrToInt('$' + formID), 6);
			except
				Result := Nil
			end;
		end else begin
			sTemp := Copy(formID, 3, 6);
		end;
		
		try
			i := StrToInt('$' + sTemp)
		except
			Result := Nil;
		end;
		
		if(Length(sTemp) = 6) then begin
			Result := RecordByFormID(file, i, true);
		end else begin
			Result := Nil;
		end;
    end;
end;

function DeleteSpaces(Str: string): string;
var
  i: Integer;
  sTest: string;
begin
  i:=0;
  sTest := Str; //Need to copy to a second var in order to access characters like an array
  while i<=Length(sTest) do
    if sTest[i]=' ' then Delete(sTest, i, 1)
    else Inc(i);
  Result:=sTest;
end;

function RemoveLeadingZeroes(S: string): string;
var
	sTest, sTemp: string;
	iCount: integer;
	bNonZeroFound: Boolean;
begin
	bNonZeroFound := False;
	sTemp := '';
	
	sTest := S; //Need to copy to a second var in order to access characters like an array
	for iCount := 1 to Length(sTest) do //Strings start at index 1
		begin
			if((sTest[iCount] <> '0') and (sTest[iCount] <> ' ')) or (bNonZeroFound <> False) then begin
				sTemp := sTemp + sTest[iCount];
				bNonZeroFound := True;
			end;
		end;
	
	Result := sTemp;
end; 


function Initialize: integer;
var
	iTemp, iFileCount, i, iSS2Index, iCount, jCount: integer;
	bIsSigValid, bAlreadyExists: boolean;
	sTempString, sRecipePath, sRequestedID, sEditorID, sMyEditorID, sSig, sName, sTemp, sKwydName: string;
	ValidSigs: TStringList;
	CheckFile, TempFile1, TempFile2, FormlistRecord, WorkshopFilterKeywordRecord, ICreated, TempRecord, Scripts, MatSwap, ITransform, IName, flst_formids, grup_flst, flst, flst_edid, flst_full, grup_kywd, kywd, kywd_edid, kywd_tnam, kywd_full, grup_stat, stat, stat_EDID, stat_Model, stat_MODL, stat_OBND, stat_OBND_x1, stat_OBND_x2, stat_OBND_y1, stat_OBND_y2, stat_OBND_z1, stat_OBND_z2, grup_cobj, cobj, cobj_edid, cobj_fvpa, thisFile, cobj_desc, cobj_cnam, cobj_fnam, cobj_bnam, cobj_ynam, cobj_znam, cobj_intv: IInterface;
begin
	slImported := TStringList.Create;
	ValidSigs := TStringList.Create;
	OptionsForm;

	if doStop then Exit;
	
	if Pos('\\?\', importFilePath)=0 then importFilePath := '\\?\'+importFilePath;  // allows program to handle very long file names
	debug := False;
	AddMessage('Using file: "'+importFilePath+'".');
	
	ValidSigs.Add('MISC');
	ValidSigs.Add('ACTI');
	ValidSigs.Add('BOOK');
	ValidSigs.Add('CONT');
	ValidSigs.Add('DOOR');
	ValidSigs.Add('FLOR');
	ValidSigs.Add('FURN');
	ValidSigs.Add('LIGH');
	ValidSigs.Add('MSTT');
	ValidSigs.Add('NOTE');
	ValidSigs.Add('NPC_');
	ValidSigs.Add('SCOL');
	ValidSigs.Add('STAT');
	ValidSigs.Add('TERM');
	
	//Find SS2.esm in load order
	iFileCount := FileCount();
	// Check the loaded files
	for i := 0 to iFileCount - 1 do begin
		thisFile := FileByIndex(i);
		
		if (Assigned(thisFile)) and (GetFileName(thisFile) = 'SS2.esm') then begin
			iSS2Index := i;
			Break;
		end;
	end;
	
	// Load the file into memory and parse it
	if FileExists(importFilePath) then begin
		slImported.LoadFromFile(importFilePath);
		
		for iCount := 1 to slImported.Count -1 do  // Start at 1 to skip the header row
		  begin
			bAlreadyExists := false;
			MyFormRecord := Nil;
			FormRecord := Nil;
			
			slRow := TStringList.Create;

			slRow.Delimiter := ',';
			slRow.StrictDelimiter := TRUE;
			slRow.DelimitedText := slImported.Strings[iCount];
			
			sRequestedID := DeleteSpaces(slRow.Strings[0]);
			
			FormRecord := GetRecordFromFormID(FileByIndex(0), RemoveLeadingZeroes(sRequestedID));
			
			if(FormRecord <> Nil) then begin
				// Do nothing
			end else begin
				//Try by EditorID
				FormRecord := GetRecordFromEditorID(FileByIndex(0), sRequestedID);
				
				if(FormRecord <> Nil) then begin
					// Do nothing
				end else begin
					//Try by EditorID but strip suffix numbers
					sTemp := Copy(sRequestedID, Length(sRequestedID) - 2, 3);
					
					if(sTemp = '001') then
						sRequestedID := Copy(sRequestedID, 1, Length(sRequestedID) - 3);
					
					FormRecord := GetRecordFromEditorID(FileByIndex(0), sRequestedID);
					//Finally, try from SS2
					if(FormRecord <> Nil) then begin
						//Do nothing
					end else begin
						FormRecord := GetRecordFromEditorID(FileByIndex(iSS2Index), sRequestedID);
						
						if(FormRecord <> Nil) then begin
							MyFormRecord := FormRecord
						end;
					end;
				end;
			end;
			
			
			if(FormRecord <> Nil) then begin
				sEditorID := EditorID(FormRecord);
				sMyEditorID := sPrefix + sEditorID;
				sSig := Signature(FormRecord);
				bIsSigValid := false;
				
				for jCount := 0 to ValidSigs.Count -1 do
				  begin
					if sSig = ValidSigs[jCount] then
					begin
					   bIsSigValid := true;
					   Break;
					end;
				  end;
				  
  
				if((Length(sEditorID) < 2) or (bIsSigValid <> True)) then begin
					AddMessage('Invalid Form Type: ' + HexFormID(FormRecord) + ', ' + sRequestedID);
					Continue;
				end else begin
					if(MyFormRecord <> Nil) then begin
						//Already exists in SS
					end else begin
						// Check if this already exists with the prefixed name
						MyFormRecord := GetRecordFromEditorID(FileByIndex(iSS2Index), sMyEditorID);
						
						if(MyFormRecord <> Nil) then begin
							// Do Nothing
						end else begin
							// Check if this exists as a kgSIM_ object
							MyFormRecord := GetRecordFromEditorID(FileByIndex(iSS2Index), 'kgSIM_' + sEditorID);
							
							if(MyFormRecord <> Nil) then begin
								// Do nothing - we're good
							end else begin
								// Check if this exists as a SS2_ object
								MyFormRecord := GetRecordFromEditorID(FileByIndex(iSS2Index), 'SS2_' + sEditorID);
								
								if(MyFormRecord <> Nil) then begin
									// Do nothing - we're good
								end else begin
									//AddMessage('Creating record ' + sMyEditorID);
									
									CheckFile := GetFile(FormRecord);
									TempFile1 := FileByIndex(0);
									TempFile2 := FileByIndex(iSS2Index);
									if((Equals(CheckFile, TempFile1) = false) AND (Equals(CheckFile, TempFile2) = false)) then begin
										// Create a fresh static to disconnect from the need for a master
										// get static group, or add if needed
										grup_stat := AddGroupBySignature(TempFile2, 'STAT');

										// add a new static
										stat := AddNewRecordToGroup(grup_stat, 'STAT');

										// get cobj elements, or add if needed
										stat_EDID := AddElementByString(stat, 'EDID');
										stat_Model := AddElementByString(stat, 'Model');
										stat_MODL := AddElementByString(stat_Model, 'MODL');
										
										sev(stat_EDID, sMyEditorID);
										sev(stat_MODL, gev(GetElement(FormRecord, 'Model\MODL')));
										
										iTemp := gev(GetElement(FormRecord, 'OBND\X1'));
										seev(stat, 'OBND\X1', iTemp);
										iTemp := gev(GetElement(FormRecord, 'OBND\X2'));
										seev(stat, 'OBND\X2', iTemp);
										iTemp := gev(GetElement(FormRecord, 'OBND\Y1'));
										seev(stat, 'OBND\Y1', iTemp);
										iTemp := gev(GetElement(FormRecord, 'OBND\Y2'));
										seev(stat, 'OBND\Y2', iTemp);
										iTemp := gev(GetElement(FormRecord, 'OBND\Z1'));
										seev(stat, 'OBND\Z1', iTemp);
										iTemp := gev(GetElement(FormRecord, 'OBND\Z2'));
										seev(stat, 'OBND\Z2', iTemp);
										
										TempRecord := stat								
									end else begin
										TempRecord := FormRecord; // We can just copy this record
									end;
									
									
									if(TempRecord <> Nil) then begin
										// Copy the record to SS2
										if(Equals(TempFile2, GetFile(TempRecord))) then begin
											// Record is already from SS
											ICreated := TempRecord;
										end else begin
											ICreated := wbCopyElementToFileWithPrefix(TempRecord, FileByIndex(iSS2Index), True, True, '', sPrefix, '');
										end;
										
										//Add/Overwrite the preview transform
										ITransform := AddElementByString(ICreated, 'PTRN');
										sev(ITransform, SmallNameEx(GetRecordFromEditorID(FileByIndex(0), 'workshop_JunkWalls')));
										
										//Ensure it has a name
										sName := DisplayName(ICreated);
										if(Length(sName) <= 1) then begin
											IName := AddElementByString(ICreated, 'FULL');
											sev(IName, slRow.Strings[1]);
										end;
											
											//Remove any scripts
										Scripts := ElementByIP(ICreated, 'VMAD\Scripts');
										if(Scripts <> Nil) then begin
											RemoveElement(ICreated, Scripts);
										end;
										
										if(ICreated <> Nil) then begin
											MyFormRecord := ICreated;
										end;
									end;
								end;
							end;
						end;
					end;
				end;	
				
				if(MyFormRecord <> Nil) then begin
					//Update the name
					sName := DisplayName(MyFormRecord);
					if(Length(sName) <= 1) then begin
						IName := AddElementByString(MyFormRecord, 'FULL');
						sev(IName, slRow.Strings[1]);
					end;
					
					//Process Recipe Keyword, Formlist, and COBJ Records
						//Build recipe path and keyword name
					sRecipePath := '';
					sKwydName := '';
					for jCount := 2 to slRow.Count -1 do
						begin
							if Length(slRow.Strings[jCount]) > 0 then begin
								sRecipePath := sRecipePath + '_' + DeleteSpaces(slRow.Strings[jCount]);
								sKwydName := slRow.Strings[jCount];
							end;
						end;
						
					WorkshopFilterKeywordRecord := GetRecordFromEditorID(FileByIndex(iFileCount - 1), 'PBP2_WorkshopMenu' + sRecipePath);					
					FormlistRecord := GetRecordFromEditorID(FileByIndex(iFileCount - 1), 'PBP2_Buildables' + sRecipePath);
					
					if(Not Assigned(WorkshopFilterKeywordRecord)) then begin
						AddMessage('Path ' + sRecipePath + ' not found. Creating.');
						//Build recipe filter keyword
						// get keyword group, or add if needed
						grup_kywd := AddGroupBySignature(FileByIndex(iFileCount - 1), 'KYWD');

						// add a new keyword
						WorkshopFilterKeywordRecord := AddNewRecordToGroup(grup_kywd, 'KYWD');
						kywd_edid := AddElementByString(WorkshopFilterKeywordRecord, 'EDID');
						kywd_full := AddElementByString(WorkshopFilterKeywordRecord, 'FULL');
						kywd_tnam := AddElementByString(WorkshopFilterKeywordRecord, 'TNAM');
						
						{EDID} sev(kywd_edid, 'PBP2_WorkshopMenu' + sRecipePath);
						{FULL} sev(kywd_full, sKwydName); 
						{TNAM} sev(kywd_tnam, 'Recipe Filter');
						
						// Create formlist
						if(Not Assigned(FormlistRecord)) then begin
							grup_flst := AddGroupBySignature(FileByIndex(iFileCount - 1), 'FLST');

							// add a new formlist
							FormlistRecord := AddNewRecordToGroup(grup_flst, 'FLST');
							flst_edid := AddElementByString(FormlistRecord, 'EDID');
							flst_full := AddElementByString(FormlistRecord, 'FULL');
							{EDID} sev(flst_edid, 'PBP2_Buildables' + sRecipePath);
							{FULL} sev(flst_full, sKwydName); //Just reuse the keyword name
						end;
						
						// get cobj group, or add if needed
						grup_cobj := AddGroupBySignature(FileByIndex(iFileCount - 1), 'COBJ');
							
						// Create COBJ
						cobj := GetRecordFromEditorID(FileByIndex(iFileCount - 1), 'PBP2_CO_' + sRecipePath);
						if(Not Assigned(cobj)) then begin
							// get cobj group, or add if needed
							grup_cobj := AddGroupBySignature(FileByIndex(iFileCount - 1), 'COBJ');

							// add a new cobj
							cobj := AddNewRecordToGroup(grup_cobj, 'COBJ');

							// get cobj elements, or add if needed
							cobj_edid := AddElementByString(cobj, 'EDID');
							cobj_fvpa := AddElementByString(cobj, 'FVPA');
							cobj_cnam := AddElementByString(cobj, 'CNAM');
							cobj_fnam := AddElementByString(cobj, 'FNAM');
							cobj_intv := AddElementByString(cobj, 'INTV');
							cobj_ynam := AddElementByString(cobj, 'YNAM');
							cobj_znam := AddElementByString(cobj, 'ZNAM');
							cobj_bnam := AddElementByString(cobj, 'BNAM');
							
							{EDID} sev(cobj_edid, 'PBP2_CO_' + sRecipePath);
							{FVPA} seev(cobj_fvpa, '[0]\Component', '000731A3');
							{FVPA} seev(cobj_fvpa, '[0]\Count', '1');
							
							{CNAM} sev(cobj_cnam, SmallNameEx(FormlistRecord));
							{FNAM} seev(cobj_fnam, '[0]', SmallNameEx(WorkshopFilterKeywordRecord));
							{INTV} seev(cobj_intv, 'Created Object Count', '1');
							
							{BNAM} sev(cobj_bnam, SmallNameEx(GetRecordFromEditorID(FileByIndex(0), 'WorkshopWorkbenchTypeDecorations')));
							{YNAM} sev(cobj_ynam, SmallNameEx(GetRecordFromEditorID(FileByIndex(0), 'UIWorkshopModeItemPickUpWood3Large')));
							{ZNAM} sev(cobj_znam, SmallNameEx(GetRecordFromEditorID(FileByIndex(0), 'UIWorkshopModeItemPutDownWood3Large')));
						end;
					end;
					
					if(FormlistRecord <> Nil) then begin
						//Make sure this item is in the formlist
						flst_formids := ElementByName(FormlistRecord, 'FormIDs');
						
						if not Assigned(flst_formids) then begin
							AddMessage('Adding ' + sEditorID + ' to ' + sRecipePath);
						  SetEditValue(ElementByIndex(Add(FormlistRecord, 'FormIDs', True), 0), Name(MyFormRecord));
						end else begin
							if not hasFormlistEntry(FormlistRecord, MyFormRecord) then begin
								AddMessage('Adding ' + sEditorID + ' to ' + sRecipePath);
								SetEditValue(ElementAssign(flst_formids, HighInteger, nil, False), Name(MyFormRecord));
							end;
						end;
					end;
				end;
			end else begin
				AddMessage('Could not find record for form ' + slRow.Strings[0]);
			end;
			
			slRow.Free;
		end;
	end else begin
		AddMessage('File ' + importFilePath + ' not found.');
    end;
end;

function Process(e: IInterface): integer;
var
	iCount, iSISIndex, iStageNum, iStageEnd, iAV, iType: integer;
	sTest1, sTest2, sTest3, sScriptName, sEditorID, sAV, sSpawnName: string;
	fPosX, fPosY, fPosZ, fRotX, fRotY, fRotZ, fScale: float;
	slRow: TStringList;
	ScriptProps, SISProperty, SISPropInfo, SISPropInfo2, SISValueHolder, SISStructHolder: IInterface;
	eScripts: IwbElement;
begin
	if doStop then Exit;
	
	
end;

function finalize: integer;
begin
	slImported.Free;
end;

end.
