{
    Run in a cell. You will be asked which layers to export.
}
unit ExportCellRefs;
    uses 'SS2\praUtilSS2';

    var
        elemCache: TList;
        layerCache: TStringList;
        layerMap: TJsonObject;

    // Called before processing
    // You can remove it if script doesn't require initialization code
    function Initialize: integer;
    begin
        Result := 0;

        layerCache := TStringList.create;
        elemCache := TList.create;
        layerMap := TJsonObject.create;
    end;

    procedure addLayers(layerList: TTreeView; jsonData: TJsonObject; parentNode: TTreeNode);
    var
        i, numRefs: integer;
        curName, displayName: string;
        curNode: TTreeNode;
        curSubData: TJsonObject;
    begin
        for i:=0 to jsonData.count-1 do begin
            curName := jsonData.Names[i];
            curSubData := jsonData.O[curName];
            numRefs := curSubData.A['refs'].count;
            if(numRefs > 0) then begin
                displayName := curName + ' ('+IntToStr(numRefs)+')';
            end else begin
                displayName := curName;
            end;
            if(parentNode = nil) then begin
                curNode := layerList.Items.AddObject(nil, displayName, curSubData);
            end else begin
                curNode := layerList.Items.AddChildObject(parentNode, displayName, curSubData);
            end;
            if(curSubData.O['layers'].count > 0) then begin
                addLayers(layerList, curSubData.O['layers'], curNode);
            end;
        end;
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

    procedure addAllChildLayers(targetList: TStringList; layerData: TJsonObject);
    var
        childLayers: TJsonArray;
        i: integer;
        curLayerName: string;
    begin
        curLayerName := layerData.S['name'];
        if(targetList.indexOf(curLayerName) >= 0) then exit;

        targetList.addObject(curLayerName, layerData);
        AddMessage('Added '+layerData.S['name']+' for exporting');
        childLayers := layerData.O['layers'];
        for i:=0 to childLayers.count-1 do begin
            curLayerName := childLayers.Names[i];
            addAllChildLayers(targetList, childLayers.O[curLayerName]);
        end;

    end;

    procedure processExporting(targetFileName: string; layerNames: TStringList; setLevelTo: string; doAppend: boolean);
    var
        mainList, lineList: TStringList;
        i, j, id: integer;
        layerName, scaleStr, posX, posY, posZ, rotX, rotY, rotZ, edid: string;
        layerData: TJsonObject;
        ref, base: IInterface;
    begin
        mainList := TStringList.create;
        if(doAppend and FileExists(targetFileName)) then begin
            mainList.LoadFromFile(targetFileName);
            mainList.add('');
        end else begin
            mainList.add('Form,Pos X,Pos Y,Pos Z,Rot X,Rot Y,Rot Z,Scale,iLevel,iStageNum,iStageEnd,iType,sVendorType,iVendorLevel,iOwnerNumber,sSpawnName,Requirements');
        end;
        
        // do refs
        for i:=0 to layerNames.count-1 do begin
            layerData := TJsonObject(layerNames.Objects[i]);
            //layerName := layerNames[i];
            AddMessage('Writing '+layerNames[i]);
            for j:=0 to layerData.A['refs'].count-1 do begin
                lineList := TStringList.create;
                id := layerData.A['refs'].I[j];
                ref := ObjectToElement(elemCache[id]);
                
                base := PathLinksTo(ref, 'NAME');
                edid := EditorID(base);
                scaleStr := GetElementEditValues(ref, 'XSCL');
                if(scaleStr = '') then begin
                    scaleStr := '1';
                end;
                
                posX := GetElementEditValues(ref, 'DATA\Position\X');
                posY := GetElementEditValues(ref, 'DATA\Position\Y');
                posZ := GetElementEditValues(ref, 'DATA\Position\Z');
                rotX := GetElementEditValues(ref, 'DATA\Rotation\X');
                rotY := GetElementEditValues(ref, 'DATA\Rotation\Y');
                rotZ := GetElementEditValues(ref, 'DATA\Rotation\Z');
                
                lineList.add(edid);
                lineList.add(posX);
                lineList.add(posY);
                lineList.add(posZ);
                lineList.add(rotX);
                lineList.add(rotY);
                lineList.add(rotZ);
                lineList.add(scaleStr);
                lineList.add(setLevelTo);
                lineList.add('');//stagenum
                lineList.add('');//stageend
                lineList.add('');//iType
                lineList.add('');//sVendorType
                lineList.add('');//iVendorLevel
                lineList.add('');//owner nr
                lineList.add('');//spawn name
                lineList.add('');//reqs
                
                lineList.Delimiter := ',';
                mainList.add(lineList.DelimitedText);
                
                lineList.free();
            end;
        end;
        
        AddMessage('Writing output file '+targetFileName);
        mainList.saveToFile(targetFileName);
        AddMessage('Finished.');
        
        mainList.free();
    end;

    procedure exportLayersHandler(Sender: TObject);
    var
        dialogResult: string;
        layerList: TTreeView;
        frm: TForm;
        n: TTreeNode;
        i: integer;
        layerNames: TStringList;
        jData: TJsonObject;
        lvlInput: TEdit;
        appendToFile: TCheckBox;
    begin

        frm := findComponentParentWindow(sender);
        layerList := TTreeView(frm.findComponent('layerList'));
        lvlInput := TEdit(frm.findComponent('lvlInput'));
        appendToFile := TCheckBox(frm.findComponent('appendToFile'));

        layerNames := TStringList.create;
        layerNames.Duplicates := dupIgnore;
        for i:=0 to layerList.Items.count-1 do begin
            n := layerList.Items.Item(i);
            if(n.selected) then begin
                jData := TJsonObject(n.Data);
                //AddMessage(n.Text + ' ' + jData.S['name']);
                addAllChildLayers(layerNames, jData);
            end;
        end;

        if(layerNames.count = 0) then begin
            AddMessage('Nothing selected');
            layerNames.free();
            exit;
        end;

        dialogResult := ShowSaveFileDialog('Save StageItemSpawns file as', 'CSV Files|*.csv|All Files|*.*');
        if(dialogResult = '') then begin
            layerNames.free();
            exit;
        end;
        
        if(ExtractFileExt(dialogResult) = '') then begin
            dialogResult := dialogResult + '.csv';
        end;

        processExporting(dialogResult, layerNames, lvlInput.text, appendToFile.checked);

        layerNames.free();
    end;

    procedure showExportGui();
    var
        frm: TForm;
        resultCode: cardinal;
        layerList: TTreeView;
        n: TTreeNode;
        selectLayersLabel, selectRefsLabel: TLabel;
        exportBtn, closeBtn: TButton;
        lvlInput: TEdit;
        appendToFile: TCheckBox;
    begin
        frm := CreateDialog('Export References', 510, 350);
        layerList := TTreeView.create(frm);
        layerList.Name := 'layerList';
        layerList.Parent := frm;
        layerList.left := 10;
        layerList.top := 10;
        layerList.width := 340;
        layerList.height := 300;
        layerList.ReadOnly := True;

        exportBtn := CreateButton(frm, 360, 10, 'Export Selected');

        CreateLabel(frm, 360, 50, 'Set Level To:');

        lvlInput := CreateInput(frm, 360, 70, '');
        lvlInput.Name := 'lvlInput';
        lvlInput.Text := '';
        
        appendToFile := CreateCheckbox(frm, 360, 100, 'Append to file');
        appendToFile.name := 'appendToFile';
        appendToFile.checked := true;

        closeBtn := CreateButton(frm, 360, 285, 'Close');

        exportBtn.width := 130;
        exportBtn.onclick := exportLayersHandler;
        closeBtn.width := 130;
        closeBtn.ModalResult := mrCancel;

{
        selectLayersLabel := CreateLabel(frm, 360, 10, '');
        selectLayersLabel.Name := 'selectLayersLabel';
        selectLayersLabel.Text := 'Selected Layers: 0';

        selectRefsLabel := CreateLabel(frm, 360, 30, '');
        selectRefsLabel.Name := 'selectRefsLabel';
        selectRefsLabel.Text := 'Selected Refs: 0';
}
        //layerList.Align := alClient;
        //layerList.DragMode := dmAutomatic;
        //layerList.BorderStyle := bsNone;
        //layerList.ShowLines := False;
        layerList.RowSelect := True;
        layerList.MultiSelect := True;
        // layerList.OnChange := TreeViewChange;

        addLayers(layerList, layerMap, nil);

        resultCode := frm.ShowModal();
    end;

    function getLayerObject(layerName: string; layerElem: IInterface): TJsonObject;
    var
        parentLayer: IInterface;
        parentObj: TJsonObject;
    begin
        if(not assigned(layerElem)) then begin
            Result := layerMap.O[layerName];
            Result.S['name'] := layerName;
            exit;
        end;

        parentLayer := pathLinksTo(layerElem, 'PNAM');
        if(not assigned(parentLayer)) then begin
            Result := layerMap.O[layerName];
            Result.S['name'] := layerName;
            exit;
        end;

        parentObj := getLayerObject(EditorID(parentLayer), parentLayer);
        Result := parentObj.O['layers'].O[layerName];
        Result.S['name'] := layerName;
    end;

    procedure processRef(e: IInterface);
    var
        layer, base: IInterface;
        layerName, sig: string;
        refIndex, layerIndex: integer;
        layerObj: TJsonObject;
    begin
        base := pathLinksTo(e, 'NAME');
        sig := Signature(base);
        if(sig = 'BNDS') or (sig = 'TXST') then begin
            AddMessage('Cannot process '+sig+', skipping '+FullPath(e));
            exit;
        end;
        // cannot: BNDS TXST
        //XLYR layer
        layer := pathLinksTo(e, 'XLYR');
        layerName := 'Default';
        if(assigned(layer)) then begin
            layerName := EditorID(layer);
        end;

        layerObj := getLayerObject(layerName, layer);
{
        layerIndex := layerCache.indexOf(layerName);
        if(layerIndex < 0) then begin
            if(assigned(layer)) then begin
                layerIndex := layerCache.add(layerName);
            end else begin
                layerIndex := layerCache.addObject(layerName, layer);
            end;
        end;
}
        refIndex := elemCache.add(e);
        layerObj.A['refs'].add(refIndex);
        //layerMap.A[layerName].add(refIndex);
    end;

    // called for every record selected in xEdit
    function Process(e: IInterface): integer;
    var
        sig: string;
    begin
        Result := 0;

        // comment this out if you don't want those messages
        // AddMessage('Processing: ' + FullPath(e));
        sig := Signature(e);
        if (sig = 'REFR') or (sig = 'ACHR') or (sig = 'PGRE') then begin
            processRef(e);
        end;
        // processing code goes here

    end;

    // Called after processing
    // You can remove it if script doesn't require finalization code
    function Finalize: integer;
    begin
        Result := 0;

        if(elemCache.count > 0) then begin
          //  AddMessage(layerMap.toJson(false));
            showExportGui();
        end;

        elemCache.free();
        layerMap.free();
        layerCache.free();
    end;

end.