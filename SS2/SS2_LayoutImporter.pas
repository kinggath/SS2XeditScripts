{
    Import spreadsheet to create a WSFW SettlementLayout form
	
	TODO
	Sort spreadsheet entries by z-index: lowest to highest
}
unit ImportStageData;

uses 'SS2\SS2Lib'; // uses praUtil	
	
var
    targetElem, targetFile: IInterface;
    itemFilePath: string;
	layoutItemsFileTextInput: TEdit;

function isResourceObject_elem(elem: IInterface): boolean;
var
	script: IInterface;
	sig: string;
	resourceVal: float;
begin
	Result := false;

	sig := Signature(elem);

	if(sig = 'SCOL') then begin
		exit;
	end;

	resourceVal := getAvByPath(elem, 'PRPS', 'WorkshopResourceObject');
	if(resourceVal > 0) then begin
		Result := true;
		exit;
	end;
end;
	
function isResourceObject_id(formFileName: string; id: cardinal): boolean;
var
	elem: IInterface;
begin
	Result := false;
	elem := getFormByFilenameAndFormID(formFileName, id);
	if(not assigned(elem)) then begin
		exit;
	end;

	Result := isResourceObject_elem(elem);
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

function getFirstScriptName(e: IInterface): string;
var
	curScript, scripts: IInterface;
	i: integer;
begin
	Result := '';
	scripts := ElementByPath(e, 'VMAD - Virtual Machine Adapter\Scripts');

	for i := 0 to ElementCount(scripts)-1 do begin
		curScript := ElementByIndex(scripts, i);

		Result := GetElementEditValues(curScript, 'scriptName');
		exit;
	end;
end;

function Initialize: integer;
begin
    if(not initSS2Lib()) then begin
        Result := 1;
        exit;
    end;
	
    Result := 0;
end;

// called for every record selected in xEdit
function Process(e: IInterface): integer;
var
    scriptName: string;
begin
    Result := 0;

    if(assigned(targetFile)) then begin
        AddMessage('Run this script on exactly one record!');
        Result := 1;
        exit;
    end;
   
    targetFile := GetFile(e);
    
    scriptName := getFirstScriptName(e);
    if(scriptName = '') then begin
        exit;
    end;
	
	// TODO - check if scriptName matches an expected layout script extension
    targetElem := e;
end;


function showConfigDialog(): boolean;
var
    resultData: TJsonObject;
    dialogLabel: string;
begin
    Result := false;

    if(assigned(targetElem)) then begin
        dialogLabel := 'Selected Layout: ' + EditorId(targetElem);
    end else begin
		//TODO - Add support for generating on the fly
        AddMessage('Must run on a layout form.');
		exit;
    end;

	resultData := ShowImportDialog(
                'Room Layout Data Import',
                dialogLabel);
			
	if(not assigned(resultData)) then begin
		exit;
	end;

	AddMessage(resultData.ToString());
	
	itemFilePath  := resultData.S['itemsFile'];
	resultData.free();

    Result := true;
end;


function ShowImportDialog(title, text: string): TJsonObject;
var
	frm: TForm;
	btnBrowseItems, btnOk, btnCancel: TButton;
	resultCode, yOffset: integer;
begin
	Result := false;
	frm := CreateDialog(title, 500, 120);

	CreateLabel(frm, 10, yOffset+12, 'Stage Items file:');
	layoutItemsFileTextInput := CreateInput(frm, 10, yOffset+30, '');
	layoutItemsFileTextInput.Name := 'InputRoomItems';
	layoutItemsFileTextInput.Text := '';
	layoutItemsFileTextInput.width := 430;

	btnBrowseItems := CreateButton(frm, 450, yOffset+28, '...');
	btnBrowseItems.OnClick := browseLayoutItemsFile;

	yOffset := yOffset + 50;

	btnOk := CreateButton(frm, 100, yOffset+10, 'Start');
	btnOk.ModalResult := mrYes;
	btnOk.Default := true;

	btnCancel := CreateButton(frm, 300, yOffset+10, 'Cancel');
	btnCancel.ModalResult := mrCancel;

	resultCode := frm.ShowModal();

	if(resultCode = mrYes) then begin
		Result := TJsonObject.create;
		Result.S['itemsFile'] := Trim(layoutItemsFileTextInput.Text);
	end;

	frm.free();
end;

procedure browseLayoutItemsFile(Sender: TObject);
var
	dialogResult: string;
begin
	dialogResult := ShowOpenFileDialog('Select Stage Items file', 'CSV Files|*.csv|All Files|*.*');
	if(dialogResult <> '') then begin
		layoutItemsFileTextInput.Text := dialogResult;
	end;
end;


	
function importItemData(itemsSheet: string): boolean;
var
    csvLines, csvCols: TStringList;
    i: integer;
    curEditorId, curLine: string;
    curSpawnObj: TJSONObject;
    AllLayoutFormScripts, targetLayoutScript, resourceObjArray, nonResObjArray, arrayToUse, curElement: IInterface;
begin
    Result := true;
    csvLines := TStringList.create;
    csvLines.LoadFromFile(itemsSheet);
	AllLayoutFormScripts := ElementByPath(targetElem, 'VMAD - Virtual Machine Adapter\Scripts');
	targetLayoutScript := ElementByIndex(AllLayoutFormScripts, 0);
	
	// TODO - We're currently just appending to the existing arrays - need to clear them out when updating
	for i:=1 to csvLines.count-1 do begin
        curLine := csvLines.Strings[i];
        if(curLine = '') then begin
            continue;
        end;

        csvCols := TStringList.create;

        csvCols.Delimiter := ',';
        csvCols.StrictDelimiter := TRUE;
        csvCols.DelimitedText := curLine;

        curEditorId := trim(csvCols[0]);
        if(curEditorId = '') then begin
            continue;
        end;

        curElement := FindObjectByEdidWithSuffix(curEditorId);
        if (not assigned(curElement)) then begin
            AddMessage('ERROR: found no Form for '+curEditorId);
            Result := false;
            csvCols.Free;
            continue;
        end;


        // pos, rot, scale
        if (csvCols.count < 8) or
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
		
		if(isResourceObject_elem(curElement)) then begin
			if(not assigned(resourceObjArray)) then begin
				resourceObjArray   := getOrCreateScriptPropArrayOfStruct(targetLayoutScript, 'WorkshopResources');
			end;
			arrayToUse := resourceObjArray;
		end else begin
			if(not assigned(nonResObjArray)) then begin
				nonResObjArray   := getOrCreateScriptPropArrayOfStruct(targetLayoutScript, 'NonResourceObjects');
			end;
			arrayToUse := nonResObjArray;
		end;
		
		curSpawnObj := TJSONObject.Create();
		curSpawnObj.F['posX'] := StrToFloat(csvCols.Strings[1]);
        curSpawnObj.F['posY'] := StrToFloat(csvCols.Strings[2]);
        curSpawnObj.F['posZ'] := StrToFloat(csvCols.Strings[3]);
        curSpawnObj.F['rotX'] := StrToFloat(csvCols.Strings[4]);
        curSpawnObj.F['rotY'] := StrToFloat(csvCols.Strings[5]);
        curSpawnObj.F['rotZ'] := StrToFloat(csvCols.Strings[6]);
        curSpawnObj.F['scale']:= StrToFloat(csvCols.Strings[7]);
		
		AddMessage(curSpawnObj.toString());
		appendSpawn(curElement, curSpawnObj, arrayToUse);

        csvCols.free();
    end;
	
    csvLines.free();
end;

procedure appendSpawn(baseElem: IInterface; itemData: TJsonObject; targetArray: IInterface);
var
	newStruct: IInterface;
begin
	newStruct := appendStructToProperty(targetArray);
	setStructMember(newStruct, 'ObjectForm', baseElem);

	setStructMemberDefault(newStruct, 'fPosX', itemData.F['posX'], 0.0);
	setStructMemberDefault(newStruct, 'fPosY', itemData.F['posY'], 0.0);
	setStructMemberDefault(newStruct, 'fPosZ', itemData.F['posZ'], 0.0);

	setStructMemberDefault(newStruct, 'fAngleX', itemData.F['rotX'], 0.0);
	setStructMemberDefault(newStruct, 'fAngleY', itemData.F['rotY'], 0.0);
	setStructMemberDefault(newStruct, 'fAngleZ', itemData.F['rotZ'], 0.0);

	setStructMemberDefault(newStruct, 'fScale', itemData.F['scale'], 1.0);
	setStructMemberDefault(newStruct, 'bForceStatic', 0.0, false);
end;


procedure cleanUp();
begin
    cleanupSS2Lib();
end;

// Called after processing
// You can remove it if script doesn't require finalization code
function Finalize: integer;
begin
    Result := 1;

    if(not showConfigDialog()) then begin
        AddMessage('Cancelled');
        cleanUp();
        exit;
    end;

    if (itemFilePath <> '') then begin
        if(not FileExists(itemFilePath)) then begin
            AddMessage('Item file '+itemFilePath+' does not exist');
            cleanUp();
            exit;
        end;
    end;


    if(not importItemData(itemFilePath)) then begin
        AddMessage('Can''t generate layout due to errors in data');
        cleanUp();
        exit;
    end;

    if(assigned(targetElem)) then begin
        // is this an override?
        if(not IsMaster(targetElem)) then begin
            AddMessage('=== WARNING === this script might not work properly on an override');
        end;
    end;

    cleanUp();
    Result := 0;
end;
end.