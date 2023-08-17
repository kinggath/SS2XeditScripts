{
    Import spreadsheet to overwrite a various types of Resource data on plot related records such as building classes and plans
}
unit ImportResources;

uses 'SS2\SS2Lib'; // uses praUtil	
uses 'SS2\CobbLibrary';
	
var
    targetElem, targetFile: IInterface;
    resourceFilePath, resourceProperty: string;
	resourcesItemsFileTextInput: TEdit;

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
	
	// TODO - check if scriptName matches an expected resources script extension
    targetElem := e;
end;


function showConfigDialog(): boolean;
var
    resultData: TJsonObject;
    dialogLabel: string;
begin
    Result := false;

    if(assigned(targetElem)) then begin
        dialogLabel := 'Selected Record: ' + EditorId(targetElem);
    end else begin
		//TODO - Add support for generating on the fly
        AddMessage('Must run on a building class, plan, levelplan, or skin form.');
		exit;
    end;

	resultData := ShowImportDialog(
                'Resource Data Import',
                dialogLabel);
			
	if(not assigned(resultData)) then begin
		exit;
	end;

	AddMessage(resultData.ToString());
	
	resourceFilePath := resultData.S['resourceFile'];
	resourceProperty := resultData.S['resourceType'];
	resultData.free();

    Result := true;
end;


function ShowImportDialog(title, text: string): TJsonObject;
var
	frm: TForm;
	btnBrowseItems, btnOk, btnCancel: TButton;
	resultCode, yOffset: integer;
	typeSelect: TComboBox;
    resourceTypeList: TStringList;
	typeInput: TEdit;
begin
	Result := false;
	frm := CreateDialog(title, 500, 240);

	CreateLabel(frm, 10, yOffset+12, 'Resource file:');
	resourcesItemsFileTextInput := CreateInput(frm, 10, yOffset+30, '');
	resourcesItemsFileTextInput.Name := 'InputResourcesFile';
	resourcesItemsFileTextInput.Text := '';
	resourcesItemsFileTextInput.width := 430;

	btnBrowseItems := CreateButton(frm, 450, yOffset+28, '...');
	btnBrowseItems.OnClick := browseResourcesFile;
	
	
	resourceTypeList := TStringList.create();
    resourceTypeList.add('ConstructionCosts');
    resourceTypeList.add('OperatingCosts');
    resourceTypeList.add('ProducedItems');
    resourceTypeList.add('SettlementResources');
	
	yOffset := yOffset + 55;
	
	CreateLabel(frm, 10, yOffset+5, 'Target Property:');    	
    typeSelect := CreateComboBox(frm, 100, yOffset, 150, resourceTypeList);
    typeSelect.Style := csDropDownList;
    typeSelect.ItemIndex := 0;	

	yOffset := yOffset + 100;

	btnOk := CreateButton(frm, 100, yOffset+10, 'Start');
	btnOk.ModalResult := mrYes;
	btnOk.Default := true;

	btnCancel := CreateButton(frm, 300, yOffset+10, 'Cancel');
	btnCancel.ModalResult := mrCancel;

	resultCode := frm.ShowModal();

	if(resultCode = mrYes) then begin
		Result := TJsonObject.create;
		Result.S['resourceFile'] := Trim(resourcesItemsFileTextInput.Text);
		Result.S['resourceType'] := Trim(resourceTypeList.Strings[typeSelect.ItemIndex]);
	end;

	frm.free();
end;

procedure browseResourcesFile(Sender: TObject);
var
	dialogResult: string;
begin
	dialogResult := ShowOpenFileDialog('Select Resources file', 'CSV Files|*.csv|All Files|*.*');
	if(dialogResult <> '') then begin
		resourcesItemsFileTextInput.Text := dialogResult;
	end;
end;


	
function importResourceData(resourceSheet, targetProperty: string): boolean;
var
    csvLines, csvCols: TStringList;
    i, iResourceCount, INT_iCount, INT_iLevel, INT_iOccupantCount, INT_iAverageItemCost, INT_iTargetVendorLevel, INT_iVirtualResourceHandling: integer;
	EDID_Item, EDID_NameHolderForm, EDID_PullOnlyFromContainerKeyword, EDID_UsageRequirements, EDID_ListHelperForm, EDID_TargetContainerKeyword, EDID_ResourceAV, STR_sTargetVendorType, curLine: string;
	FLT_fAmount: float;
	
    tempScriptProp, AllFormScripts, targetScript, resourceArray, obj_Item, obj_NameHolderForm, obj_PullOnlyFromContainerKeyword, obj_UsageRequirements, obj_ListHelperForm, obj_TargetContainerKeyword, obj_ResourceAV, newStruct: IInterface;
begin
    Result := true;
    csvLines := TStringList.create;
    csvLines.LoadFromFile(resourceSheet);
	AllFormScripts := ElementByPath(targetElem, 'VMAD - Virtual Machine Adapter\Scripts');
	targetScript := ElementByIndex(AllFormScripts, 0);
	
	// Clear out previous
	if(getScriptProp(targetScript, targetProperty) <> nil) then begin
		deleteScriptProp(targetScript, targetProperty);
	end;
	
	
	// Now iterate through and generate our data
	for i:=1 to csvLines.count-1 do begin
        curLine := csvLines.Strings[i];
        if(curLine = '') then begin
            continue;
        end;

        csvCols := TStringList.create;

        csvCols.Delimiter := ',';
        csvCols.StrictDelimiter := TRUE;
        csvCols.DelimitedText := curLine;
		
		if(not assigned(resourceArray)) then begin
			resourceArray   := getOrCreateScriptPropArrayOfStruct(targetScript, targetProperty);
		end;
		
		
		if((targetProperty = 'OperatingCosts') or (targetProperty = 'ConstructionCosts')) then begin
			// Item
			EDID_Item := trim(csvCols[3]);
				
			if(EDID_Item = '') then begin
				// Can't skip this ever
				continue;
			end;

			obj_Item := FindObjectByEdid(EDID_Item);
			if (not assigned(obj_Item)) then begin
				AddMessage('********ERROR********: found no Form for '+EDID_Item);
				Result := false;
				csvCols.Free;
				continue;
			end;
			
			// NameHolderForm [Optional]
			EDID_NameHolderForm := trim(csvCols[4]);
		
			if(EDID_NameHolderForm <> '') then begin
				obj_NameHolderForm := FindObjectByEdid(EDID_NameHolderForm);
				if (not assigned(obj_NameHolderForm)) then begin
					AddMessage('ERROR: found no Form for '+EDID_NameHolderForm);
					Result := false;
					csvCols.Free;
					continue;
				end;
			end;
			
			// PullOnlyFromContainerKeyword [Optional]
			EDID_PullOnlyFromContainerKeyword := trim(csvCols[5]);
		
			if(EDID_PullOnlyFromContainerKeyword <> '') then begin
				obj_PullOnlyFromContainerKeyword := FindObjectByEdid(EDID_PullOnlyFromContainerKeyword);
				if (not assigned(obj_PullOnlyFromContainerKeyword)) then begin
					AddMessage('ERROR: found no Form for '+EDID_PullOnlyFromContainerKeyword);
					Result := false;
					csvCols.Free;
					continue;
				end;
			end;
			
			// UsageRequirements [Optional]
			EDID_UsageRequirements := trim(csvCols[6]);
		
			if(EDID_UsageRequirements <> '') then begin
				obj_UsageRequirements := FindObjectByEdid(EDID_UsageRequirements);
				if (not assigned(obj_UsageRequirements)) then begin
					AddMessage('ERROR: found no Form for '+EDID_UsageRequirements);
					Result := false;
					csvCols.Free;
					continue;
				end;
			end;
			
			iResourceCount := iResourceCount + 1;
        
			AddMessage('Adding item ' + curLine);
			
			newStruct := appendStructToProperty(resourceArray);
			setStructMemberDefault(newStruct, 'iCount', StrToInt(csvCols[0]), 1);
			setStructMemberDefault(newStruct, 'iLevel', StrToInt(csvCols[1]), -1);
			setStructMemberDefault(newStruct, 'iOccupantCount', StrToInt(csvCols[2]), 1);
			setStructMember(newStruct, 'Item', obj_Item);
			
			if(assigned(obj_NameHolderForm)) then begin
				setStructMember(newStruct, 'NameHolderForm', obj_NameHolderForm);
			end;
			
			if(assigned(obj_PullOnlyFromContainerKeyword)) then begin
				setStructMember(newStruct, 'PullOnlyFromContainerKeyword', obj_PullOnlyFromContainerKeyword);
			end;
			
			if(assigned(obj_UsageRequirements)) then begin
				setStructMember(newStruct, 'UsageRequirements', obj_UsageRequirements);
			end;
		end else if(targetProperty = 'ProducedItems') then begin
			// Item
			EDID_Item := trim(csvCols[5]);
				
			if(EDID_Item = '') then begin
				// Can't skip this ever
				continue;
			end;

			obj_Item := FindObjectByEdid(EDID_Item);
			if (not assigned(obj_Item)) then begin
				AddMessage('********ERROR********: found no Form for '+EDID_Item);
				Result := false;
				csvCols.Free;
				continue;
			end;
			
			// ListHelperForm [Optional]
			EDID_ListHelperForm := trim(csvCols[6]);
		
			if(EDID_ListHelperForm <> '') then begin
				obj_ListHelperForm := FindObjectByEdid(EDID_ListHelperForm);
				if (not assigned(obj_ListHelperForm)) then begin
					AddMessage('ERROR: found no Form for '+EDID_ListHelperForm);
					Result := false;
					csvCols.Free;
					continue;
				end;
			end;
			
			// NameHolderForm [Optional]
			EDID_NameHolderForm := trim(csvCols[7]);
		
			if(EDID_NameHolderForm <> '') then begin
				obj_NameHolderForm := FindObjectByEdid(EDID_NameHolderForm);
				if (not assigned(obj_NameHolderForm)) then begin
					AddMessage('ERROR: found no Form for '+EDID_NameHolderForm);
					Result := false;
					csvCols.Free;
					continue;
				end;
			end;
			
			// TargetContainerKeyword [Optional]
			EDID_TargetContainerKeyword := trim(csvCols[9]);
		
			if(EDID_TargetContainerKeyword <> '') then begin
				obj_TargetContainerKeyword := FindObjectByEdid(EDID_TargetContainerKeyword);
				if (not assigned(obj_TargetContainerKeyword)) then begin
					AddMessage('ERROR: found no Form for '+EDID_TargetContainerKeyword);
					Result := false;
					csvCols.Free;
					continue;
				end;
			end;
			
			// UsageRequirements [Optional]
			EDID_UsageRequirements := trim(csvCols[10]);
		
			if(EDID_UsageRequirements <> '') then begin
				obj_UsageRequirements := FindObjectByEdid(EDID_UsageRequirements);
				if (not assigned(obj_UsageRequirements)) then begin
					AddMessage('ERROR: found no Form for '+EDID_UsageRequirements);
					Result := false;
					csvCols.Free;
					continue;
				end;
			end;
			
			iResourceCount := iResourceCount + 1;
        
			AddMessage('Adding item ' + curLine);
			
			newStruct := appendStructToProperty(resourceArray);
			
			if(csvCols[0] <> '') then begin
				setStructMemberDefault(newStruct, 'iAverageItemCost', StrToFloat(csvCols[0]), -1.0);
			end;
			
			setStructMemberDefault(newStruct, 'iCount', StrToInt(csvCols[1]), 1);
			setStructMemberDefault(newStruct, 'iLevel', StrToInt(csvCols[2]), -1);
			setStructMemberDefault(newStruct, 'iOccupantCount', StrToInt(csvCols[3]), 1);
			
			if(csvCols[4] <> '') then begin
				setStructMemberDefault(newStruct, 'iTargetVendorLevel', StrToInt(csvCols[4]), 0);
			end;
			
			if(csvCols[8] <> '') then begin
				setStructMemberDefault(newStruct, 'sTargetVendorType', StrToInt(csvCols[8]), 0);
			end;
			
			setStructMember(newStruct, 'Item', obj_Item);
			
			if(assigned(obj_ListHelperForm)) then begin
				setStructMember(newStruct, 'ListHelperForm', obj_ListHelperForm);
			end;
			
			if(assigned(obj_NameHolderForm)) then begin
				setStructMember(newStruct, 'NameHolderForm', obj_NameHolderForm);
			end;
			
			if(assigned(obj_TargetContainerKeyword)) then begin
				setStructMember(newStruct, 'TargetContainerKeyword', obj_TargetContainerKeyword);
			end;
			
			if(assigned(obj_UsageRequirements)) then begin
				setStructMember(newStruct, 'UsageRequirements', obj_UsageRequirements);
			end;
		end else if(targetProperty = 'SettlementResources') then begin
			// ResourceAV
			EDID_ResourceAV := trim(csvCols[4]);
				
			if(EDID_ResourceAV = '') then begin
				// Can't skip this ever
				continue;
			end;

			obj_ResourceAV := FindObjectByEdid(EDID_ResourceAV);
			if (not assigned(obj_ResourceAV)) then begin
				AddMessage('********ERROR********: found no Form for '+EDID_ResourceAV);
				Result := false;
				csvCols.Free;
				continue;
			end;
			
			// UsageRequirements [Optional]
			EDID_UsageRequirements := trim(csvCols[10]);
		
			if(EDID_UsageRequirements <> '') then begin
				obj_UsageRequirements := FindObjectByEdid(EDID_UsageRequirements);
				if (not assigned(obj_UsageRequirements)) then begin
					AddMessage('ERROR: found no Form for '+EDID_UsageRequirements);
					Result := false;
					csvCols.Free;
					continue;
				end;
			end;
			
			iResourceCount := iResourceCount + 1;
        
			AddMessage('Adding item ' + curLine);
			
			newStruct := appendStructToProperty(resourceArray);
			setStructMemberDefault(newStruct, 'fAmount', StrToFloat(csvCols[0]), 0.0);
			setStructMemberDefault(newStruct, 'iLevel', StrToInt(csvCols[1]), -1);
			setStructMemberDefault(newStruct, 'iOccupantCount', StrToInt(csvCols[2]), 1);
			setStructMemberDefault(newStruct, 'iVirtualResourceHandling', StrToInt(csvCols[3]), 0);
			
			setStructMember(newStruct, 'ResourceAV', obj_ResourceAV);
			
			if(assigned(obj_UsageRequirements)) then begin
				setStructMember(newStruct, 'UsageRequirements', obj_UsageRequirements);
			end;
		end;

        csvCols.free();
    end;
	
	if((iResourceCount = 0) and (getScriptProp(targetScript, targetProperty) <> nil)) then begin
		deleteScriptProp(targetScript, targetProperty);
	end;
	
    csvLines.free();
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

    if (resourceFilePath <> '') then begin
        if(not FileExists(resourceFilePath)) then begin
            AddMessage('Item file '+resourceFilePath+' does not exist');
            cleanUp();
            exit;
        end;
    end;


    if(not importResourceData(resourceFilePath, resourceProperty)) then begin
        AddMessage('Can''t generate resources due to errors in data');
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