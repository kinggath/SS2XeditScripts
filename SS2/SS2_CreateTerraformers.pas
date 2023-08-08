{
    Run on a material swap in your addon file. It will ask you for a name
}
unit CreateTerraformers;

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
        terraformerName: string;
    begin
        Result := 0;
        if (Signature(e) <> 'MSWP') then exit;
        
        
        if(not InputQuery('Create Terraformers', 'Input name for terraformer for matswap '+EditorID(e), terraformerName)) then begin
            AddMessage('Skipping '+EditorID(e));
            exit;
        end;
        
        // comment this out if you don't want those messages
        AddMessage('Processing: ' + EditorID(e));

        // processing code goes here
        // procedure generateTerraformers(tfName: string; edidBase: string; targetFile: IInterface; matSwap: IInterface);
        generateTerraformers(terraformerName, '', EditorID(e), GetFile(e), e);

    end;

    // Called after processing
    // You can remove it if script doesn't require finalization code
    function Finalize: integer;
    begin
        cleanupSS2Lib();
        Result := 0;
    end;

end.