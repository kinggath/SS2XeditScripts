{
    Run on city plan layout
}
unit userscript;
    uses praUtil;
    
    
    procedure processLayout(layoutScript: IInterface);
    var
        iMinLevel, i: integer;
        ExtraData_Numbers01: IInterface;
        curNumberEntry: IInterface;
        fNumber, fNumberNew: float;
    begin
        iMinLevel := getScriptPropDefault(layoutScript, 'iMinLevel', 0);
        fNumberNew := iMinLevel * 1.0;
        ExtraData_Numbers01 := getScriptProp(layoutScript, 'ExtraData_Numbers01');
        
        if(not assigned(ExtraData_Numbers01)) then begin
            exit;
        end;
        
        for i:=0 to ElementCount(ExtraData_Numbers01)-1 do begin
            curNumberEntry := ElementByIndex(ExtraData_Numbers01, i);
            fNumber := getStructMemberDefault(curNumberEntry, 'fNumber', 0);
            
            if(fNumber <> fNumberNew) then begin
                // AddMessage('yes mismatch '+IntToStr(iMinLevel)+' vs '+FloatToStr(getStructMember(curNumberEntry, 'fNumber')));
                setStructMember(curNumberEntry, 'fNumber', fNumberNew);
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
        layoutScript: IInterface;
    begin
        Result := 0;
        
        layoutScript := getScript(e, 'SimSettlementsV2:Weapons:CityPlanLayout');
        if(not assigned(layoutScript)) then begin
            exit;
        end;

        // comment this out if you don't want those messages
        AddMessage('Processing: ' + FullPath(e));
        processLayout(layoutScript);

        // processing code goes here

    end;

    // Called after processing
    // You can remove it if script doesn't require finalization code
    function Finalize: integer;
    begin
        Result := 0;
    end;

end.