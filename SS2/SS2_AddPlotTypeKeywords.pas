{
    Run on SS2 plots (the Weapons) to add missing type keywords
}
unit AddPlotTypeKeywords;
    uses praUtil;
    uses SS2Lib;

    // Called before processing
    // You can remove it if script doesn't require initialization code
    function Initialize: integer;
    begin
        Result := 0;
        if(not initSS2Lib()) then begin
            AddMessage('initSS2Lib failed!');
            Result := 1;
            exit;
        end;
    end;

    // called for every record selected in xEdit
    function Process(e: IInterface): integer;
    var
        script: IInterface;
        curPlotType: integer;
    begin
        Result := 0;
        
        script := getScript(e, 'SimSettlementsV2:Weapons:BuildingPlan');
        if(not assigned(script)) then exit;
        
        curPlotType := getPlotTypeFromKeywords(e);
        if(curPlotType > 0) then begin
            AddMessage('Bla '+intToStr(curPlotType));
            exit;
        end;
        
        curPlotType := getPlotTypeFromFormLists(e);
        if(curPlotType <= 0) then begin
            AddMessage('Failed to find type of plot '+EditorID(e));
            exit;
        end;
        
        

        AddMessage('Applying type '+getNameForPackedPlotType(curPlotType)+' to '+EditorID(e));
        stripTypeKeywords(e);
        setTypeKeywords(e, curPlotType);

    end;

    // Called after processing
    // You can remove it if script doesn't require finalization code
    function Finalize: integer;
    begin
        Result := 0;
        cleanupSS2Lib();
    end;

end.