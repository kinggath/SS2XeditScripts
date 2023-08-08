unit FindPluginInCityPlanItems;

uses 'SS2\praUtilSS2';

var
  bInputEntered: boolean;
  search_string: string;
  currentFile: IInterface;


function Initialize: Integer;
begin
  // Prompt the user for the search string
  bInputEntered := InputQuery('Find Plugin', 'Enter search string:', search_string);
end;


function Process(e: IInterface): Integer;
var
  i: Integer;
  vmad, scripts, script, prop: IInterface;
  value_type: string;
begin
	// Record current element file
	currentFile := GetFile(e);
  // Get the VMAD element from the record
  vmad := ElementBySignature(e, 'VMAD');
  // Get the Scripts element from the VMAD element
  scripts := ElementByName(vmad, 'Scripts');

  // Iterate through the script entries in the Scripts element
  for i := 0 to ElementCount(scripts) - 1 do begin
    script := ElementByIndex(scripts, i);
    prop := getScriptProp(script, 'NonResourceObjects');
    if(assigned(prop)) then begin
		findItemsFromPlugin(prop);
	end;
  end;
end;

procedure findItemsFromPlugin(aItemArray: IInterface);
var
    i, iFormID: integer;
    curItem, originalPluginForm, thisPluginForm, formIDMember, pluginNameMember: IInterface;
    FormPlugin: string;
begin
	for i:=0 to ElementCount(aItemArray)-1 do begin
		curItem := ElementByIndex(aItemArray, i);
		FormPlugin := getStructMember(curItem, 'sPluginName');
		iFormID := getStructMember(curItem, 'iFormID');
		//AddMessage(IntToStr(i) + ' ' + FormPlugin + ' vs search string: ' + search_string);
		if(FormPlugin = search_string) then begin
			originalPluginForm := getFormByFileAndFormID(FindFile(search_string), iFormID);
			thisPluginForm := FindObjectInFileByEdid(currentFile, EditorID(originalPluginForm));
			
			AddMessage('Found plugin at index ' + IntToStr(i) + ' form: ' + IntToHex(iFormID, 8) + ' ' + EditorID(originalPluginForm));
			
			if(assigned(thisPluginForm)) then begin
				AddMessage('Successfully found that form!');
				setStructMember(curItem, 'ObjectForm', thisPluginForm);
				
				formIDMember := getRawStructMember(curItem, 'iFormID');
				if(assigned(formIDMember)) then begin
					RemoveElement(curItem, formIDMember);
				end;
				
				pluginNameMember := getRawStructMember(curItem, 'sPluginName');
				if(assigned(pluginNameMember)) then begin
					RemoveElement(curItem, pluginNameMember);
				end;
			end;
		end;
	end;
end;

end.
