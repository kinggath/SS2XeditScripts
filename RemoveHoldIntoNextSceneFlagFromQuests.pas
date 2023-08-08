{
    New script template, only shows processed records
    Assigning any nonzero value to Result will terminate script
}
unit userscript;
    const 
        // the bad flag is 128
        FLAG_TO_REMOVE = 128;

    // Called before processing
    // You can remove it if script doesn't require initialization code
    function Initialize: integer;
    begin
        Result := 0;
    end;

    // called for every record selected in xEdit
    function Process(e: IInterface): integer;
    var
        actions, action: IInterface;
        i: integer;
        curFlags: cardinal;
    begin
        Result := 0;
        
        if(Signature(e) <> 'SCEN') then exit;

        // comment this out if you don't want those messages
        //AddMessage('Processing: ' + FullPath(e));
        
        actions := ElementByPath(e, 'Actions');

        for i:=0 to ElementCount(actions)-1 do begin
            action := ElementByIndex(actions, i);
            curFlags := GetElementNativeValues(action, 'FNAM');
            if (curFlags and FLAG_TO_REMOVE) <> 0 then begin
                curFlags := (curFLags and (not FLAG_TO_REMOVE));
                //AddMessage(GetElementEditValues(action, 'ANAM')+' '+IntToStr(curFlags));
                SetElementNativeValues(action, 'FNAM', curFlags);
				
				AddMessage('Flag found: ' + FullPath(e));
            end;
        end;

    end;

    // Called after processing
    // You can remove it if script doesn't require finalization code
    function Finalize: integer;
    begin
        Result := 0;
    end;

end.