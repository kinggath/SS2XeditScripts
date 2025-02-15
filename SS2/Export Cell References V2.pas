{
    Run in a cell. You will be asked which layers to export.
    
    File ExportCellRefsReplace.txt can be used for replacement.
}
unit ExportCellRefs;
    uses 'SS2\praUtil';

    const
        configFile = ScriptsPath + 'SS2\ExportCellRefs.cfg';
        replaceFile = ScriptsPath + 'SS2\ExportCellRefsReplace.txt';

    var
        elemCache: TList;
        layerCache: TStringList;
        layerMap: TJsonObject;
        MousePosX, MousePosY: integer;
        layerList: TTreeView;
        menuSelectedNode: TTreeNode;

        settingDoReplace: boolean;
        settingNumSeparatorLines: integer;
        settingSortEntries: boolean;
        settingAutoFlagClutter: boolean;
        
        replaceMap: TJsonObject;
        
        
    procedure registerReplacement(search: string; replace: string);
    var
        searchLc: string;
    begin
        searchLc := LowerCase(search);
        replaceMap.S[searchLc] := replace;
    end;
    
    function getReplacement(search: string): string;
    var
        searchLc: string;
    begin
        searchLc := LowerCase(search);
        Result := replaceMap.S[searchLc];
        
        if(Result = '') then begin
            Result := search;
        end;
    end;

    procedure loadReplacements();
    var
        i, j, breakPos: integer;
        curLine, curKey, curVal: string;
        lines : TStringList;
    begin
        // default
        settingDoReplace := true;
        settingNumSeparatorLines := 3;
        settingSortEntries := true;
        settingAutoFlagClutter := true;

        if(not FileExists(replaceFile)) then begin
            exit;
        end;
        lines := TStringList.create;
        lines.LoadFromFile(replaceFile);

        for i:=0 to lines.count-1 do begin
            curLine := lines[i];
            breakPos := -1;

            for j:=1 to length(curLine) do begin
                if(curLine[j] = '=') then begin
                    breakPos := j;
                    break;
                end;
            end;

            if breakPos <> -1 then begin
                curKey := trim(copy(curLine, 0, breakPos-1));
                curVal := trim(copy(curLine, breakPos+1, length(curLine)));

                registerReplacement(curKey, curVal);
            end;
        end;

        lines.free();
    end;

    procedure loadConfig();
    var
        i, j, breakPos: integer;
        curLine, curKey, curVal: string;
        lines : TStringList;
    begin
        // default
        settingDoReplace := true;
        settingNumSeparatorLines := 3;
        settingSortEntries := true;
        settingAutoFlagClutter := true;

        if(not FileExists(configFile)) then begin
            exit;
        end;
        lines := TStringList.create;
        lines.LoadFromFile(configFile);

        for i:=0 to lines.count-1 do begin
            curLine := lines[i];
            breakPos := -1;

            for j:=1 to length(curLine) do begin
                if(curLine[j] = '=') then begin
                    breakPos := j;
                    break;
                end;
            end;

            if breakPos <> -1 then begin
                curKey := trim(copy(curLine, 0, breakPos-1));
                curVal := trim(copy(curLine, breakPos+1, length(curLine)));

                if(curKey = 'settingDoReplace') then begin
                    settingDoReplace := StrToBool(curVal);
                end else if(curKey = 'settingSortEntries') then begin
                    settingSortEntries := StrToBool(curVal);
                end else if(curKey = 'settingAutoFlagClutter') then begin
                    settingAutoFlagClutter := StrToBool(curVal);
                end else if(curKey = 'settingNumSeparatorLines') then begin
                    settingNumSeparatorLines := StrToInt(curVal);
                end;
            end;
        end;

        lines.free();
    end;


    procedure saveConfig();
    var
        lines : TStringList;
    begin
        lines := TStringList.create;


        lines.add('settingDoReplace='+BoolToStr(settingDoReplace));
        lines.add('settingSortEntries='+BoolToStr(settingSortEntries));
        lines.add('settingAutoFlagClutter='+BoolToStr(settingAutoFlagClutter));
        lines.add('settingNumSeparatorLines='+IntToStr(settingNumSeparatorLines));

        lines.saveToFile(configFile);
        lines.free();
    end;


    // Called before processing
    // You can remove it if script doesn't require initialization code
    function Initialize: integer;
    begin
        if(PRA_UTIL_VERSION < 15.0) then begin
            AddMessage('This script requires praUtil version 15.0 or newer, '+FloatToStr(PRA_UTIL_VERSION)+' found instead.');
            Result := 1;
            exit;
        end;
        Result := 0;


        layerCache := TStringList.create;
        elemCache := TList.create;
        layerMap := TJsonObject.create;
        replaceMap := TJsonObject.create;
    end;

    function CreateSaveItemsFileDialog(title: string; filter: string = ''; doOverwrite: boolean): TSaveDialog;
    var
        objFile: TSaveDialog;
    begin
        objFile := TSaveDialog.Create(nil);
        Result := nil;

        objFile.Title := title;
        if(doOverwrite) then begin
            objFile.Options := objFile.Options + [ofOverwritePrompt];
        end;


        if(filter <> '') then begin
            objFile.Filter := filter;
            objFile.FilterIndex := 1;
        end;
        Result := objFile;
    end;

    function ShowSaveItemsFileDialog(title: string; doOverwrite: boolean): string;
    var
        objFile: TSaveDialog;
    begin
        objFile := CreateSaveItemsFileDialog(title, 'CSV Files|*.csv|All Files|*.*', doOverwrite);
        Result := '';
        try
            if objFile.Execute then begin
                Result := objFile.FileName;
            end;
        finally
            objFile.free;
        end;
    end;

    function getLayerDisplayName(jsonData: TJsonObject; selection: integer): string;
    var
        numRefs: integer;
        actualName: string;
    begin
        actualName := jsonData['name'];
        numRefs := jsonData.A['refs'].count;
        if(numRefs > 0) then begin
            Result := actualName + ' (' + IntToStr(numRefs) + ')';
        end else begin
            Result := actualName;
        end;

        if(selection > 0) then begin
            Result := '['+IntToStr(selection)+'] '+Result;
        end else begin
            Result := '[_] '+Result;
        end;
    end;

    procedure selectAllChildren(layerData: TJsonObject; select: integer);
    var
        i: integer;
        curName: string;
    begin
        //if(layerData.O['layers'].count == 0) then exit;

        for i:=0 to layerData.O['layers'].count-1 do begin
            curName := layerData.O['layers'].names[i];
            layerData.O['layers'].O[curName].I['selected'] := select;

            selectAllChildren(layerData.O['layers'].O[curName], select);
        end;
    end;

    procedure selectAllLayers(select: integer);
    var
        i: integer;
        curName: string;
    begin
        for i:=0 to layerMap.count-1 do begin
            curName := layerMap.names[i];
            layerMap.O[curName].I['selected'] := select;

            selectAllChildren(layerMap.O[curName], select);
        end;
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
            {
            numRefs := curSubData.A['refs'].count;
            if(numRefs > 0) then begin
                displayName := curName + ' ('+IntToStr(numRefs)+')';
            end else begin
                displayName := curName;
            end;
            }
            displayName := getLayerDisplayName(curSubData, false);

            if(parentNode = nil) then begin
                curNode := layerList.Items.AddObject(nil, displayName, curSubData);
            end else begin
                curNode := layerList.Items.AddChildObject(parentNode, displayName, curSubData);
            end;

            curNode.ImageIndex := i;
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

    procedure copyEntryObject(src, dst: TJsonObject);
    begin
        dst.S['form']  := src.S['form'];
        dst.S['pos_X'] := src.S['pos_X'];
        dst.S['pos_Y'] := src.S['pos_Y'];
        dst.S['pos_Z'] := src.S['pos_Z'];
        dst.S['rot_X'] := src.S['rot_X'];
        dst.S['rot_Y'] := src.S['rot_Y'];
        dst.S['rot_Z'] := src.S['rot_Z'];
        dst.S['scale'] := src.S['scale'];
    end;

    procedure swapArrayObjects(arr: TJsonArray; s, e: integer);
    var
        test, sO, eO: TJsonObject;
    begin
        test := TJsonObject.create();

        sO := arr.O[s];
        eO := arr.O[e];

        copyEntryObject(sO, test);
        copyEntryObject(eO, sO);
        copyEntryObject(test, eO);



        test.free();
    end;

    procedure sortFormEntryArray(arr: TJsonArray);
    var
        s, e, i, smallestIndex, largestIndex: integer;
        cmpSmall, cmpLarge, cmpCur: string;
    begin
        s := 0;
        e := arr.count-1;
        // AddMessage('sorting array from 0 to '+IntToStr(e));
        // fuck this shit, I'm doing some slow-ass shit sorting
        while(e-s >= 2) do begin

            smallestIndex := s;

            cmpSmall := arr.O[s].S['form'];

            // AddMessage('Iterating from '+IntToStr(s)+' to '+IntToStr(e));
            for i := s+1 to e do begin
                cmpCur := arr.O[i].S['form'];

                if(cmpCur < cmpSmall) then begin
                    smallestIndex := i;
                    cmpSmall := cmpCur;
                end;

            end;

            // do something
            if(smallestIndex <> s) then begin
                // swap
                swapArrayObjects(arr, s, smallestIndex);
                // end else begin
                // AddMessage('got the smallest == largest. probably all are equal, doesn''t matter');
            end;

            s := s + 1;
        end;

    end;

    procedure addEmptyLines(toList: TStringList; numLines: integer);
    var
        i:integer;
    begin
        for i:=1 to numLines do begin
            toList.add('');
        end;
    end;

    procedure processExporting(targetFileName: string; layerNames: TStringList);
    var
        mainList, lineList: TStringList;
        i, j, id, level: integer;
        layerName, scaleStr, posX, posY, posZ, rotX, rotY, rotZ, edid, levelName, typeString: string;
        layerData: TJsonObject;
        ref, base: IInterface;

        preSortedEntries, curEntry: TJsonObject;
        levelArray: TJsonArray;

        isFirst: boolean;
    begin
        {

        settingSortEntries: boolean;
        settingAutoFlagClutter: boolean;
        }
        mainList := TStringList.create;
        if((not settingDoReplace) and FileExists(targetFileName)) then begin
            mainList.LoadFromFile(targetFileName);
            addEmptyLines(mainList, settingNumSeparatorLines);
        end else begin
            mainList.add('Form,Pos X,Pos Y,Pos Z,Rot X,Rot Y,Rot Z,Scale,iLevel,iStageNum,iStageEnd,iType,sVendorType,iVendorLevel,iOwnerNumber,sSpawnName,Requirements');
        end;

        // pre-sort by level
        preSortedEntries := TJsonObject.create;
        for i:=0 to layerNames.count-1 do begin

            layerData := TJsonObject(layerNames.Objects[i]);
            level := layerData.I['selected'];
            //layerName := layerNames[i];

            for j:=0 to layerData.A['refs'].count-1 do begin

                id := layerData.A['refs'].I[j];
                ref := ObjectToElement(elemCache[id]);

                base := PathLinksTo(ref, 'NAME');
                edid := getReplacement(EditorID(base));
                
                //

                curEntry := preSortedEntries.A[level].addObject();

                curEntry.S['form'] := edid;
                curEntry.S['pos_X'] := GetElementEditValues(ref, 'DATA\Position\X');
                curEntry.S['pos_Y'] := GetElementEditValues(ref, 'DATA\Position\Y');
                curEntry.S['pos_Z'] := GetElementEditValues(ref, 'DATA\Position\Z');

                curEntry.S['rot_X'] := GetElementEditValues(ref, 'DATA\Rotation\X');
                curEntry.S['rot_Y'] := GetElementEditValues(ref, 'DATA\Rotation\Y');
                curEntry.S['rot_Z'] := GetElementEditValues(ref, 'DATA\Rotation\Z');

                scaleStr := GetElementEditValues(ref, 'XSCL');
                if(scaleStr = '') then begin
                    scaleStr := '1';
                end;
                curEntry.S['scale'] := scaleStr;
                // curEntry.F['level'] := GetElementNativeValues(ref, 'XSCL');
            end;
        end;

        isFirst := true;

        for level:=1 to 3 do begin
            levelArray := preSortedEntries.A[level];
            if(levelArray.count = 0) then continue;

            if(isFirst) then begin
                isFirst := false;
            end else begin
                addEmptyLines(mainList, settingNumSeparatorLines);
                //mainList.add('');
                //mainList.add('');
                //mainList.add('');
            end;

            if(settingSortEntries) then begin
                sortFormEntryArray(levelArray);
            end;
            for i:=0 to levelArray.count-1 do begin
                curEntry := levelArray.O[i];
                lineList := TStringList.create;
                
                typeString := '';
                if(settingAutoFlagClutter) then begin
                    if(strContainsCI(curEntry.S['form'], 'clutter')) then begin
                        typeString := '9';
                    end;
                end;
                

                lineList.add(curEntry.S['form']);
                lineList.add(curEntry.S['pos_X']);
                lineList.add(curEntry.S['pos_Y']);
                lineList.add(curEntry.S['pos_Z']);
                lineList.add(curEntry.S['rot_X']);
                lineList.add(curEntry.S['rot_Y']);
                lineList.add(curEntry.S['rot_Z']);
                lineList.add(curEntry.S['scale']);
                lineList.add(IntToStr(level));
                lineList.add('');//stagenum
                lineList.add('');//stageend
                lineList.add(typeString);//iType
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

        preSortedEntries.free();
        mainList.free();
    end;

    procedure exportLayersHandler(Sender: TObject);
    var
        dialogResult, dialogCaption: string;
        layerList: TTreeView;
        frm: TForm;
        n: TTreeNode;
        i, numExtraLines: integer;
        layerNames: TStringList;
        jData: TJsonObject;
        numLinesInput: TLabeledEdit;
        doSortEntries, autoFlagClutter: TCheckBox;
        writeMode: TRadioGroup;
        isAppendMode: boolean;
    begin

        {autoFlagClutter := CreateCheckbox(frm, 360, yOffset, 'Auto-flag Clutter');
        autoFlagClutter.name := 'doSortEntries';
        autoFlagClutter.checked := settingAutoFlagClutter;}

        frm := findComponentParentWindow(sender);
        layerList := TTreeView(frm.findComponent('layerList'));

        doSortEntries := TCheckBox(frm.findComponent('doSortEntries'));
        settingSortEntries := doSortEntries.checked;

        autoFlagClutter := TCheckBox(frm.findComponent('autoFlagClutter'));
        settingAutoFlagClutter := autoFlagClutter.checked;

        writeMode := TRadioGroup(frm.findComponent('writeMode'));
        numLinesInput := TLabeledEdit(frm.findComponent('numLinesInput'));

        numExtraLines := 0;
        if(numLinesInput.text <> '') then begin
            numExtraLines := StrToInt(numLinesInput.text);
            settingNumSeparatorLines := numExtraLines;
        end;

        // isAppendMode := appendToFile.checked;
        isAppendMode := writeMode.ItemIndex = 1;
        settingDoReplace := (not isAppendMode);

        {
        settingDoReplace: boolean;
        settingNumSeparatorLines: integer;
        settingSortEntries: boolean;
        }

        saveConfig();


        layerNames := TStringList.create;
        layerNames.Duplicates := dupIgnore;
        layerNames.sorted := true;

        for i:=0 to layerList.Items.count-1 do begin
            n := layerList.Items.Item(i);
            jData := TJsonObject(n.Data);

            if(jData.I['selected'] > 0) then begin
                //AddMessage(n.Text + ' ' + jData.S['name']);
                //addAllChildLayers(layerNames, jData);
                layerNames.addObject(jData.S['name'], jData);
                AddMessage('Added '+jData.S['name']+' for exporting');
            end;
        end;

        if(layerNames.count = 0) then begin
            AddMessage('Nothing selected');
            layerNames.free();
            exit;
        end;

        if(isAppendMode) then begin
            dialogCaption := 'Select StageItemsSpawns to append';
        end else begin
            dialogCaption := 'Save StageItemSpawns file as';
        end;

        dialogResult := ShowSaveItemsFileDialog(dialogCaption, (not isAppendMode));
        if(dialogResult = '') then begin
            layerNames.free();
            exit;
        end;

        if(ExtractFileExt(dialogResult) = '') then begin
            dialogResult := dialogResult + '.csv';
        end;

        processExporting(dialogResult, layerNames);

        layerNames.free();
    end;

    procedure layerListMouseDownHandler(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    begin
        // AddMessage('mouse handler fires');
        MousePosX := X;
        MousePosY := Y;
    end;


    procedure layerListMouseMoveHandler(Sender: TObject; Shift: TShiftState; X, Y: Integer);
    begin
        MousePosX := X;
        MousePosY := Y;
    end;



    procedure redrawCheckboxes(layerList: TTreeView);
    var
        i: integer;
        n: TTreeNode;
        jData: TJsonObject;
        displayName: string;
    begin
        layerList.items.beginUpdate();
        for i:=0 to layerList.Items.count-1 do begin
            n := layerList.Items.Item(i);

            jData := TJsonObject(n.Data);

            displayName := getLayerDisplayName(jData, jData.I['selected']);
            if(n.text <> displayName) then begin
                n.text := displayName;
            end;
        end;
        layerList.items.endUpdate();
    end;

    procedure setSelectionByNode(node: TTreeNode; select: integer);
    var
        jData: TJsonObject;
    begin
        jData := TJsonObject(node.Data);



        jData.I['selected'] := select;
        selectAllChildren(jData, jData.I['selected']);

        redrawCheckboxes(layerList);
    end;


    procedure menuSetCurrent1Handler(sender: TObject);
    begin
        if(menuSelectedNode = nil) then exit;
        setSelectionByNode(menuSelectedNode, 1);
    end;

    procedure menuSetCurrent2Handler(sender: TObject);
    begin
        if(menuSelectedNode = nil) then exit;
        setSelectionByNode(menuSelectedNode, 2);
    end;

    procedure menuSetCurrent3Handler(sender: TObject);
    begin
        if(menuSelectedNode = nil) then exit;
        setSelectionByNode(menuSelectedNode, 3);
    end;

    procedure menuSetCurrentNoneHandler(sender: TObject);
    begin
        if(menuSelectedNode = nil) then exit;
        setSelectionByNode(menuSelectedNode, 0);
    end;

    procedure menuSetAll1Handler(sender: TObject);
    begin
        selectAllLayers(1);
        redrawCheckboxes(layerList);
    end;

    procedure menuSetAll2Handler(sender: TObject);
    begin
        selectAllLayers(2);
        redrawCheckboxes(layerList);
    end;

    procedure menuSetAll3Handler(sender: TObject);
    begin
        selectAllLayers(3);
        redrawCheckboxes(layerList);
    end;

    procedure menuSelectNoneHandler(sender: TObject);
    begin
        selectAllLayers(0);
        redrawCheckboxes(layerList);
    end;



    procedure popupEventHandler(sender: TObject);
    var
        n: TTreeNode;
        rect: TRect;
        haveItem: boolean;
        setCurrent1Item, setCurrent2Item, setCurrent3Item, setCurrentNoneItem: TMenuItem;
        setAll1Item, setAll2Item, setAll3Item, setAllNoneItem: TMenuItem;
    begin

        //AddMEssage('wat '+sender.name);
        //AddMEssage('wat '+IntToStr(Mouse.CursorPos.Y));
        menuSelectedNode := nil;
        haveItem := false;
        n := layerList.GetNodeAt(MousePosX, MousePosY);
        if(nil <> n) then begin
            rect := n.DisplayRect(true);

            if(
                (rect.Left <= MousePosX) and
                (rect.Top <= MousePosY) and
                (rect.Right >= MousePosX) and
                (rect.Bottom >= MousePosY)
            ) then begin
                menuSelectedNode := n;

                haveItem := true;
            end;
        end;

        // try shit
        setCurrent1Item := TMenuItem(sender.findComponent('setCurrent1Item'));
        setCurrent2Item := TMenuItem(sender.findComponent('setCurrent2Item'));
        setCurrent3Item := TMenuItem(sender.findComponent('setCurrent3Item'));
        setCurrentNoneItem := TMenuItem(sender.findComponent('setCurrentNoneItem'));

        // setCurrent1Item := TMenuItem.create(menu);

        if(haveItem) then begin
            setCurrent1Item.enabled := true;
            setCurrent2Item.enabled := true;
            setCurrent3Item.enabled := true;
            setCurrentNoneItem.enabled := true;
        end else begin
            setCurrent1Item.enabled := false;
            setCurrent2Item.enabled := false;
            setCurrent3Item.enabled := false;
            setCurrentNoneItem.enabled := false;
        end;
    end;



    procedure showExportGui();
    var
        frm: TForm;
        resultCode: cardinal;
        n: TTreeNode;
        selectLayersLabel, selectRefsLabel: TLabel;
        exportBtn, closeBtn, browseBtn: TButton;
        lvlInput, numLinesInput: TLabeledEdit;
        doSortEntries, autoFlagClutter: TCheckBox;
        menu: TPopupMenu;


        setCurrent1Item, setCurrent2Item, setCurrent3Item, setCurrentNoneItem: TMenuItem;
        setAll1Item, setAll2Item, setAll3Item, setAllNoneItem: TMenuItem;
        separator, selectAllItem, selectNoneItem: TMenuItem;

        yOffset, dialogHeight: integer;


        writeMode: TRadioGroup;
    begin
        loadReplacements();
        loadConfig();
        {        settingDoReplace := true;
        settingNumSeparatorLines := 3;
        settingSortEntries := true;}

        dialogHeight := 460;
        frm := CreateDialog('Export References', 514, dialogHeight);
        layerList := TTreeView.create(frm);
        layerList.Name := 'layerList';
        layerList.Parent := frm;
        layerList.left := 10;
        layerList.top := 10;
        layerList.width := 340;
        layerList.height := dialogHeight-60;
        layerList.ReadOnly := True;
        // layerList.onclick := layerListClickHandler;
        layerList.onMouseDown := layerListMouseDownHandler;
        layerList.onMouseMove := layerListMouseMoveHandler;

        // menu
        menu  := TPopupMenu.Create(layerList);
        menu.Name := 'menu';
        menu.OnPopup := popupEventHandler;
        layerList.PopupMenu  := menu;

        setCurrent1Item := TMenuItem.create(menu);
        setCurrent1Item.Name := 'setCurrent1Item';
        setCurrent1Item.caption := 'Set to Level 1';
        setCurrent1Item.onclick := menuSetCurrent1Handler;
        menu.Items.add(setCurrent1Item);

        setCurrent2Item := TMenuItem.create(menu);
        setCurrent2Item.Name := 'setCurrent2Item';
        setCurrent2Item.caption := 'Set to Level 2';
        setCurrent2Item.onclick := menuSetCurrent2Handler;
        menu.Items.add(setCurrent2Item);

        setCurrent3Item := TMenuItem.create(menu);
        setCurrent3Item.Name := 'setCurrent3Item';
        setCurrent3Item.caption := 'Set to Level 3';
        setCurrent3Item.onclick := menuSetCurrent3Handler;
        menu.Items.add(setCurrent3Item);

        setCurrentNoneItem := TMenuItem.create(menu);
        setCurrentNoneItem.Name := 'setCurrentNoneItem';
        setCurrentNoneItem.caption := 'Clear Level';
        setCurrentNoneItem.onclick := menuSetCurrentNoneHandler;
        menu.Items.add(setCurrentNoneItem);


        separator := TMenuItem.create(menu);
        separator.caption := '-';
        menu.Items.add(separator);



        setAll1Item := TMenuItem.create(menu);
        setAll1Item.Name := 'setAll1Item';
        setAll1Item.caption := 'Set All to Level 1';
        setAll1Item.onclick := menuSetAll1Handler;
        menu.Items.add(setAll1Item);

        setAll2Item := TMenuItem.create(menu);
        setAll2Item.Name := 'setAll2Item';
        setAll2Item.caption := 'Set All to Level 2';
        setAll2Item.onclick := menuSetAll2Handler;
        menu.Items.add(setAll2Item);

        setAll3Item := TMenuItem.create(menu);
        setAll3Item.Name := 'setAll3Item';
        setAll3Item.caption := 'Set All to Level 3';
        setAll3Item.onclick := menuSetAll3Handler;
        menu.Items.add(setAll3Item);


        setAllNoneItem := TMenuItem.create(menu);
        setAllNoneItem.Name := 'setAllNoneItem';
        setAllNoneItem.caption := 'Clear Level for All';
        setAllNoneItem.onclick := menuSelectNoneHandler;
        menu.Items.add(setAllNoneItem);


        yOffset := 10;
        writeMode := CreateRadioGroup(frm, 360, yOffset, 130, 70, 'Writing Mode', nil);
        writeMode.Items.Add('Replace');
        writeMode.Items.Add('Append');
        writeMode.Name := 'writeMode';
        if(settingDoReplace) then begin
            writeMode.ItemIndex := 0;
        end else begin
            writeMode.ItemIndex := 1;
        end;

        yOffset := yOffset + 110;
        numLinesInput := CreateLabelledInput(frm, 360, yOffset, 130, 30, 'Num Separator Lines', IntToStr(settingNumSeparatorLines));
        numLinesInput.Name := 'numLinesInput';
        yOffset := yOffset + 40;

        doSortEntries := CreateCheckbox(frm, 360, yOffset, 'Sort Entries');
        doSortEntries.name := 'doSortEntries';
        doSortEntries.checked := settingSortEntries;

        yOffset := yOffset + 30;

        autoFlagClutter := CreateCheckbox(frm, 360, yOffset, 'Auto-flag Clutter');
        autoFlagClutter.name := 'autoFlagClutter';
        autoFlagClutter.checked := settingAutoFlagClutter;


        // appendToFile.checked := true;

        yOffset := dialogHeight - 106;

        //yOffset := 254;
        exportBtn := CreateButton(frm, 360, yOffset, '-> Export Selected');
        yOffset := yOffset + 24;

        closeBtn := CreateButton(frm, 360, yOffset+8, 'Close');

        exportBtn.width := 130;
        exportBtn.onclick := exportLayersHandler;
        closeBtn.width := 130;
        closeBtn.ModalResult := mrCancel;


        //layerList.RowSelect := True;
        //layerList.MultiSelect := True;
        // layerList.OnChange := TreeViewChange;

        addLayers(layerList, layerMap, nil);
        //layerListClickHandler(layerList);

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

    end;

    function cloneJsonArrayAndSort(oldArr: TJsonArray): TJsonArray;
    var
        i, j, prevType: integer;
        curName: string;
        tempList: TStringList;
    begin
        Result := TJsonArray.create();
        for i:=0 to oldArr.count - 1 do begin
            prevType := oldArr.Types[i];
            case prevType of
                JSON_TYPE_STRING:
                    Result.add(oldArr.S[i]);
                JSON_TYPE_INT:
                    Result.add(oldArr.I[i]);
                JSON_TYPE_LONG:
                    Result.add(oldArr.L[i]);
                JSON_TYPE_ULONG:
                    Result.add(oldArr.U[i]);
                JSON_TYPE_FLOAT:
                    Result.add(oldArr.F[i]);
                JSON_TYPE_DATETIME:
                    Result.add(oldArr.D[i]);
                JSON_TYPE_BOOL:
                    Result.add(oldArr.B[i]);
                JSON_TYPE_ARRAY:
                    Result.add(cloneJsonArrayAndSort(oldArr.A[i]));
                JSON_TYPE_OBJECT:
                    Result.add(sortJsonObject(oldArr.O[i]));
            end;
        end;
    end;

    function sortJsonObject(oldObj: TJsonObject): TJsonObject;
    var
        i, prevType: integer;
        curName: string;
        tempList: TStringList;
    begin
        tempList := TStringList.create();
        tempList.sorted := true;
        Result := TJsonObject.create();

        for i:=0 to oldObj.count-1 do begin
            curName := oldObj.Names[i];
            tempList.add(curName);
        end;


        for i:=0 to tempList.count-1 do begin
            curName := tempList[i];
            prevType := oldObj.Types[curName];
            case prevType of
                JSON_TYPE_STRING:
                    Result.S[curName] := oldObj.S[curName];
                JSON_TYPE_INT:
                    Result.I[curName] := oldObj.I[curName];
                JSON_TYPE_LONG:
                    Result.L[curName] := oldObj.L[curName];
                JSON_TYPE_ULONG:
                    Result.U[curName] := oldObj.U[curName];
                JSON_TYPE_FLOAT:
                    Result.F[curName] := oldObj.F[curName];
                JSON_TYPE_DATETIME:
                    Result.D[curName] := oldObj.D[curName];
                JSON_TYPE_BOOL:
                    Result.B[curName] := oldObj.B[curName];
                JSON_TYPE_ARRAY:
                    Result.A[curName] := cloneJsonArrayAndSort(oldObj.A[curName]);
                JSON_TYPE_OBJECT:
                    Result.O[curName] := sortJsonObject(oldObj.O[curName]);
            end;
        end;
        tempList.free();
    end;

    function Finalize: integer;
    var
        tmpJsonMap: TJsonObject;
    begin
        Result := 0;

        if(elemCache.count > 0) then begin
            tmpJsonMap := layerMap;
            layerMap := sortJsonObject(tmpJsonMap);
            tmpJsonMap.free();
            showExportGui();
        end;

        elemCache.free();
        layerMap.free();
        layerCache.free();
        
        replaceMap.free();

    end;

end.