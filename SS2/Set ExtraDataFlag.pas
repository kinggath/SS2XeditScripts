{
    Run on some forms, it will edit city plans in-place
}
unit userscript;
    uses 'SS2\praUtil';
    
    procedure processCityPlan(layoutScript: IInterface; baseForm: IInterface);
    var
        NonResourceObjects, curStruct, curForm: IInterface;
        i: integer;
    begin
        // find the thing
        NonResourceObjects := getScriptProp(layoutScript, 'NonResourceObjects');
        if(not assigned(NonResourceObjects)) then exit;
        
        for i:=0 to ElementCount(NonResourceObjects)-1 do begin
            curStruct := ElementByIndex(NonResourceObjects, i);
            curForm := getStructMember(curStruct, 'ObjectForm');
            if(assigned(curForm)) then begin
                if(isSameForm(curForm, baseForm)) then begin
                    AddMessage('Found it in struct #'+IntToStr(i));
                    setStructMember(curStruct, 'fExtraDataFlag', 1);
                end;
            end;
        end;
    end;

    // Called before processing
    // You can remove it if script doesn't require initialization code
    function Initialize: integer;
    begin
        Result := 0;
    end;

    // called for every record selected in xEdit
    function Process(e: IInterface): integer;
    var
        i, numRefs: integer;
        curRef, cityPlanScript: IInterface;
    begin
        Result := 0;
        
        // comment this out if you don't want those messages
        
        numRefs := ReferencedByCount(e)-1;
        for i := 0 to numRefs do begin
            curRef := ReferencedByIndex(e, i);
            cityPlanScript := getScript(curRef, 'SimSettlementsV2:Weapons:CityPlanLayout');
            if(assigned(cityPlanScript)) then begin
                AddMessage('Processing: ' + FullPath(curRef));
                processCityPlan(cityPlanScript, e);
            end;
        end;

        // processing code goes here

    end;

    // Called after processing
    // You can remove it if script doesn't require finalization code
    function Finalize: integer;
    begin
        Result := 0;
    end;

end.