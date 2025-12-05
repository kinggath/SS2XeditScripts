{
    Run this on a City Plan to transfer its data to a different City Plan. 
    This can be used to update an existing city plan by stamping data from a newly generated
    plan onto an old one.
}
unit userscript;
    uses praUtil;

    const
        CITY_PLAN_SCRIPT = 'SimSettlementsV2:Weapons:CityPlan';
        CACHE_FILE_NAME = ScriptsPath + 'Transfer City Plan Properties.cache';

    var
        allCityPlansCache: TList;


    procedure loadCache();
    var
        loadingHelper: TStringList;
        i: integer;
        curForm: IInterface;
    begin
        // spawnMiscData.LoadFromFile(CACHE_FILE_NAME);
        
        if(allCityPlansCache <> nil) then exit;

        if(not FileExists(CACHE_FILE_NAME)) then begin
            exit;
        end;
        loadingHelper := TStringList.create;
        loadingHelper.LoadFromFile(CACHE_FILE_NAME);
        allCityPlansCache := TList.create();
        
        for i:=0 to loadingHelper.count-1 do begin
        
            curForm := AbsStrToForm(loadingHelper[i]);
            if(assigned(curForm)) then begin
                allCityPlansCache.add(curForm);
            end;
        end;
        
        AddMessage('Loaded cache from '+CACHE_FILE_NAME);
        

        loadingHelper.free();

    end;

    procedure saveCache();
    var
        loadingHelper: TStringList;
        i: integer;
    begin
        if(allCityPlansCache = nil) then exit;

        loadingHelper := TStringList.create;
        
        for i:=0 to allCityPlansCache.count-1 do begin
            loadingHelper.add(FormToAbsStr(ObjectToElement(allCityPlansCache[i])));
        end;
        
        
        loadingHelper.saveToFile(CACHE_FILE_NAME);
        loadingHelper.free();
    end;

    // Called before processing
    // You can remove it if script doesn't require initialization code
    function Initialize: integer;
    begin
        allCityPlansCache := nil;
        loadCache();
        Result := 0;
    end;


    procedure findCityPlansInGroup(curFile: IInterface; sig: string);
    var
        grp, curEntry, script: IInterface;
        j: integer;
    begin
        grp := GroupBySignature(curFile, sig);

        if(not assigned(grp)) then exit;

        for j:=0 to ElementCount(grp)-1 do begin
            curEntry := ElementByIndex(grp, j);
            script := getScript(curEntry, CITY_PLAN_SCRIPT);
            if(assigned(script)) then begin
                allCityPlansCache.add(curEntry);
            end;
        end;
    end;

    procedure buildListOfCityPlans();
    var
        i, j, curIndex: integer;
        curFile, weapGroup, curWeap, plotScript: IInterface;
        ss2File: IInterface;
        curEdid: string;
    begin
        if(allCityPlansCache <> nil) then exit;

        allCityPlansCache := TList.create;

        AddMessage('Building city plan list (this might take a while)');
        for i := 0 to FileCount-1 do begin
            curFile := FileByIndex(i);


            if (HasMaster(curFile, 'SS2.esm')) then begin
                findCityPlansInGroup(curFile, 'WEAP');
                findCityPlansInGroup(curFile, 'MISC');
            end;

        end;
        AddMessage('Finished city plan list building');
        saveCache();
    end;

    procedure fillPlanList(clb: TCheckListBox; except_this: string);
    var
        i, j, curIndex: integer;
        curFile, weapGroup, curWeap, plotScript: IInterface;
        curEdid: string;
    begin
        //allBuildingPlansCache
        buildListOfCityPlans();

        for i := 0 to allCityPlansCache.count-1 do begin
            curWeap := ObjectToElement(allCityPlansCache[i]);
            curEdid := EditorID(curWeap);
            if(curEdid <> except_this) then begin
                curIndex := clb.Items.addObject(curEdid + ' "'+GetElementEditValues(curWeap, 'FULL')+'"', curWeap);
            end;
        end;
    end;

    {

}
    function selectTargetCityPlan(except_this: string): IInterface;
    var
        frm: TForm;
        clb: TCheckListBox;
        i: integer;
    begin
        Result := nil;
        // prepare list
        frm := frmFileSelect;
        frm.Width := 800;
        frm.Height := 500;

 //       selectedEdid := trim(plotEdidInput.Text);
        // frm.onresize := resourceListResize;
        try
            frm.Caption := 'Select target city plan';
            clb := TCheckListBox(frm.FindComponent('CheckListBox1'));
            // clb.multiSelect := false;
            //clb.Items.Add('<new file>');
            fillPlanList(clb, except_this);

            if (frm.ShowModal = mrOk) then begin

                for i := 0 to clb.Items.Count-1 do begin
                    if clb.Checked[i] then begin
                        Result := ObjectToElement(clb.Items.Objects[i]);
                        // selectedEdid := EditorID(selectedElem);
                        break;
                    end;
                end;
            end;
        finally
//            realSender.enabled := true;
            frm.Free;
        end;
        {
        }
    end;

    procedure transferStruct(srcStruct, dstStruct: IInterface);
    var
        i: integer;
        child: IInterface;
        curName: string;
    begin
        // seems to work
        ElementAssign(dstStruct, LowInteger, srcStruct, false);
        {
        exit;
        // original:
        
    
    
        // AddMessage('What the fuck');
        // dumpElem(srcStruct);
         for i := 0 to ElementCount(srcStruct)-1 do begin
            child := ElementByIndex(srcStruct, i);
            curName := geevt(child, 'memberName');
            // AddMessage(curName+'='+GetEditValue(child));
            
            setStructMember(dstStruct, curName, getStructMember(srcStruct, curName));
            
            
            
           //SetElementEditValues(srcStruct, curName, getElementEditValues(dstStruct, curName));
        end;
        }
    end;


    procedure transferArrayOfStruct(srcScript, dstScript: IInterface; propName: string);
    var
        srcArray, dstArray: IInterface;
        srcStruct, dstStruct: IInterface;
        i: integer;
    begin
        srcArray := getScriptProp(srcScript, propName);
        if (not assigned(srcArray)) then begin
            // remove from destination
            AddMessage('Property '+propName+' not found in source');
            deleteScriptProp(dstScript, propName);
            exit;
        end;
        
        AddMessage('Transferring property '+propName);
        // dumpElem(srcArray);
        // exit;
        
        dstArray := getOrCreateScriptProp(dstScript, propName, 'Array of Struct');
        clearScriptProp(dstScript, propName);

        for i:=0 to ElementCount(srcArray)-1 do begin
            AddMessage('Transferring struct #'+IntToStr(i+1)+'/'+IntToStr(ElementCount(srcArray)));
            
            srcStruct := ElementByIndex(srcArray, i);
            
            // dstStruct := ElementAssign(dstArray, HighInteger, srcStruct, false);
            
            
            
            dstStruct := appendStructToProperty(dstArray);
            transferStruct(srcStruct, dstStruct);
            
        end;

    end;

    procedure transferLayoutProperties(src, dst: IInterface);
    var
        srcScript, dstScript: IInterface;
    begin
        AddMessage('Transferring data from '+EditorID(src)+' to '+EditorID(dst));
        srcScript := getScript(src, 'SimSettlementsV2:Weapons:CityPlanLayout');
        dstScript := getScript(dst, 'SimSettlementsV2:Weapons:CityPlanLayout');

        // scalars
        {
        iIndexOffset
        iMinLevel
        iRemoveAtLevel
        }
        setScriptProp(dstScript, 'iIndexOffset', getScriptPropDefault(srcScript, 'iIndexOffset', 0));
        setScriptProp(dstScript, 'iMinLevel', getScriptPropDefault(srcScript, 'iMinLevel', 0));
        setScriptProp(dstScript, 'iRemoveAtLevel', getScriptPropDefault(srcScript, 'iRemoveAtLevel', 0));

        // array of struct
        transferArrayOfStruct(srcScript, dstScript, 'NonResourceObjects');
        transferArrayOfStruct(srcScript, dstScript, 'WorkshopResources');
        transferArrayOfStruct(srcScript, dstScript, 'PowerConnections');
		transferArrayOfStruct(srcScript, dstScript, 'SurviveLayoutChangeData');
        transferArrayOfStruct(srcScript, dstScript, 'ExtraData_Forms01');
        transferArrayOfStruct(srcScript, dstScript, 'ExtraData_Forms02');
        transferArrayOfStruct(srcScript, dstScript, 'ExtraData_Forms03');
        transferArrayOfStruct(srcScript, dstScript, 'ExtraData_Numbers01');
        transferArrayOfStruct(srcScript, dstScript, 'ExtraData_Numbers02');
        transferArrayOfStruct(srcScript, dstScript, 'ExtraData_Numbers03');
        transferArrayOfStruct(srcScript, dstScript, 'ExtraData_Strings01');
        transferArrayOfStruct(srcScript, dstScript, 'ExtraData_Strings02');
        transferArrayOfStruct(srcScript, dstScript, 'ExtraData_Strings03');
        transferArrayOfStruct(srcScript, dstScript, 'ExtraData_Bools01');
        transferArrayOfStruct(srcScript, dstScript, 'ExtraData_Bools02');
        transferArrayOfStruct(srcScript, dstScript, 'ExtraData_Bools03');
        // transferArrayOfStruct(srcScript, dstScript, 'ExtraData_Forms01');

        {

        NonResourceObjects
        WorkshopResources
        PowerConnections
		SurviveLayoutChangeData
        ExtraData_Forms01
        ExtraData_Forms02
        ExtraData_Forms03
        ExtraData_Forms01
        ExtraData_Numbers01
        ExtraData_Numbers02
        ExtraData_Numbers03
        ExtraData_Strings01
        ExtraData_Strings02
        ExtraData_Strings03
        ExtraData_Bools01
        ExtraData_Bools02
        ExtraData_Bools03
        }
    end;

    procedure processSourceCityPlan(sourcePlan: IInterface);
    var
        targetPlan: IInterface;

        sourceLayouts, targetLayouts: IInterface;
        sourceScript, targetScript: IInterface;
        sourceLayout, targetLayout: IInterface;

        i: integer;
    begin
        targetPlan := selectTargetCityPlan(EditorID(sourcePlan));
        AddMessage('Source Plan: '+EditorID(sourcePlan));
        AddMessage('Target Plan: '+EditorID(targetPlan));

        sourceScript := getScript(sourcePlan, CITY_PLAN_SCRIPT);
        targetScript := getScript(targetPlan, CITY_PLAN_SCRIPT);

        sourceLayouts := getScriptProp(sourceScript, 'Layouts');
        targetLayouts := getScriptProp(targetScript, 'Layouts');

        if (ElementCount(sourceLayouts) <> ElementCount(targetLayouts)) then begin
            AddMessage('Plans have different number of layouts!');
            exit;
        end;

        for i:=0 to ElementCount(sourceLayouts)-1 do begin
            sourceLayout := getObjectFromProperty(sourceLayouts, i);
            targetLayout := getObjectFromProperty(targetLayouts, i);
            transferLayoutProperties(sourceLayout, targetLayout);
        end;

    end;

    // called for every record selected in xEdit
    function Process(e: IInterface): integer;
    var
        script: IInterface;
    begin
        Result := 0;

        script := getScript(e, CITY_PLAN_SCRIPT);
        if (assigned(script)) then begin
            processSourceCityPlan(e);
        end;


    end;

    // Called after processing
    // You can remove it if script doesn't require finalization code
    function Finalize: integer;
    begin
        Result := 0;
        if(allCityPlansCache <> nil) then begin
            allCityPlansCache.free();
        end;
    end;
end.
