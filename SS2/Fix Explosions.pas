{
    New script template, only shows processed records
    Assigning any nonzero value to Result will terminate script
}
unit userscript;
    
    uses 'SS2\praUtilSS2';
    
    // Called before processing
    // You can remove it if script doesn't require initialization code
    function Initialize: integer;
    begin
        Result := 0;
    end;

    // called for every record selected in xEdit
    function Process(e: IInterface): integer;
    var
        flags: IInterface;
    begin
        Result := 0;

        if(Signature(e) <> 'EXPL') then exit;
        // comment this out if you don't want those messages
        AddMessage('Processing: ' + FullPath(e));
        flags := ElementByPath(e, 'DATA\Flags');
        if(GetElementEditValues(flags, 'Always Uses World Orientation') = '1') then begin
            SetElementEditValues(flags, 'Always Uses World Orientation' ,'0');
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