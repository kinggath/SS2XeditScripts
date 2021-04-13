{
    New script template, only shows processed records
    Assigning any nonzero value to Result will terminate script
}
unit userscript;
    uses 'SS2\SS2Lib'; // uses praUtil

    const
        // mainName = 'SS2.esm'; = ss2Filename
        extName = 'SS2Extended.esp';
        extArchive = 'SS2Extended - Main.ba2';

    var
        extFile: IInterface;
        SS2_Template_ExplosionDebris: IInterface;// one for each level, put into extended
        SS2_Template_BuildingExplosionChain: IInterface; //dito?
        SS2_Template_BuildingExplosion: IInterface;

    // Called before processing
    // You can remove it if script doesn't require initialization code
    function Initialize: integer;
    begin
        Result := 0;

        if(not initSS2Lib()) then begin
            Result := 1;
            exit;
        end;

        // mainFile :=
        extFile := FileByName(extName);
        if(not assigned(extFile)) then begin
            Result := 1;
            addMessage('Could not find '+extName);
            exit;
        end;

        SS2_Template_ExplosionDebris := FindObjectInFileByEdid(ss2masterFile, 'SS2_Template_ExplosionDebris');
        SS2_Template_BuildingExplosionChain := FindObjectInFileByEdid(ss2masterFile, 'SS2_Template_BuildingExplosionChain');
        SS2_Template_BuildingExplosion := FindObjectInFileByEdid(ss2masterFile, 'SS2_Template_BuildingExplosion');
    end;

    function generateExplosionNifName(meshName: string): string;
    var
        parts: TStringList;
        basePath: string;
        lastI: integer;
    begin
        Result := '';
        parts := TStringList.create;
        
        AddMessage('OldName '+meshName);

        parts.Delimiter := '\';
        parts.StrictDelimiter := True; // Spaces excluded from being a delimiter
        parts.DelimitedText := meshName;
        
        // Conversions
        // SS2\BuildingPlans\Industrial\2x2\BranchingPlans\Wood\MagazinePress01\FinalL3.NIF -> SS2Extended\ExplosionDebris\Buildings\Industrial\2x2\BranchingPlans\Wood\MagazinePress01\FinalL3.NIF
        // SS2\BuildingPlans\Recreational\2x2\Uit_EnduranceTraining\UitEND_EndTP_L1_Finale_SCOL.NIF -> SS2Extended\ExplosionDebris\Buildings\
        
        // basePath := 'SS2Extended\ExplosionDebris\Buildings\'+plotTypeName+'\'+sizeStr+'\';

        if(parts.count > 1) then begin
            // SS2\BuildingPlans becomes SS2Extended\ExplosionDebris\Buildings
            parts[0] := 'ExplosionDebris';
            parts[1] := 'Buildings';
            
            Result := 'SS2Extended\' + parts.DelimitedText;
            
            // lastI := parts.count - 1;
            // Result := basePath + parts[lastI - 1] + '\' + parts[lastI];
        end;
        
        parts.free;
    end;

    function findExplosionNifName(meshName: string): string;
    var
        mainType, plotSize: integer;
        plotTypeName, sizeStr, curPath: string;
        i, j: integer;
    begin
        Result := '';
        
        curPath := generateExplosionNifName(meshName);
        if(curPath = '') then begin
            AddMessage('Failed to generate explosion nif path');
            exit;
        end;
        
        if(not ResourceExists('Meshes\'+curPath)) then begin
            AddMessage('Could not find '+curPath+', no explosion data will be created');
            exit;
        end;
        
        Result := curPath;
    end;
    
    function getModelFromPlan(planScript: IInterface): IInterface;
    var
        StageModels, maybeResult: IInterface;
        numModels: integer;
    begin
        Result := nil;
        StageModels := getScriptProp(planScript, 'StageModels');
        if(not assigned(StageModels)) then begin
            exit;
        end;

        numModels := ElementCount(StageModels);
        
        if(numModels <= 0) then begin
            exit;
        end;
        
        maybeResult := getObjectFromProperty(StageModels, numModels - 1);
        if(Signature(maybeResult) = 'STAT') then begin
            Result := maybeResult;
        end;
    end;
    
    function getModelFromSkin(planScript: IInterface): IInterface;
    var
        StageModels, maybeResult: IInterface;
        numModels: integer;
    begin
        Result := nil;

        maybeResult := getScriptProp(planScript, 'ReplaceStageModel');
        if(assigned(maybeResult)) then begin
            if(Signature(maybeResult) = 'STAT') then begin
                Result := maybeResult;
            end;
        end;
    end;
    
    procedure processPlanOrSkin(e, model, script: IInterface);
    var
        matSwap: IInterface;
        meshName, explMeshName, edidBase: string;
        exDebris, exChain, exKaboom: IInterface;
    begin
        meshName := GetElementEditValues(model, 'Model\MODL');
        matSwap  := pathLinksTo(model, 'Model\MODS');

        explMeshName := findExplosionNifName(meshName);

        if(explMeshName = '') then exit;

        AddMessage('Found explosion mesh name: ' + explMeshName+' for '+EditorID(e));

        edidBase := EditorID(e);

        exDebris := getCopyOfTemplate(extFile, SS2_Template_ExplosionDebris, GenerateEdid('', edidBase+'_ExplosionDebris'));
        exChain  := getCopyOfTemplate(extFile, SS2_Template_BuildingExplosionChain, GenerateEdid('', edidBase+'_ExplosionDebrisChain'));
        exKaboom := getCopyOfTemplate(extFile, SS2_Template_BuildingExplosion, GenerateEdid('', edidBase+'_Explosion'));

        // put stuff in
        SetElementEditValues(exDebris, 'Model\MODL', explMeshName);
        if(assigned(matSwap)) then begin
            setPathLinksTo(exDebris, 'Model\MODS', matSwap);
        end;
        
        setPathLinksTo(exChain, 'DATA\Placed Object', exDebris);
        setPathLinksTo(exKaboom, 'DATA\Placed Object', exChain);

        // now the actual building plan
        setUniversalForm(script, 'DemolitionExplosionOverride', exKaboom);
    end;
    
    procedure processLevelSkin(e, script: IInterface);
    var
        model: IInterface;
    begin
        model := getModelFromSkin(script);
        if(not assigned(model)) then begin
            exit;
        end;
        AddMessage('Got model ');
        dumpElem(model);
        
        processPlanOrSkin(e, model, script);
    end;

    procedure processLevelPlan(e, script: IInterface);
    var
        model: IInterface;
    begin
        model := getModelFromPlan(script);
        
        if(not assigned(model)) then begin
            exit;
        end;
        
        processPlanOrSkin(e, model, script);
    end;

    // called for every record selected in xEdit
    function Process(e: IInterface): integer;
    var
        plotRoot, script: IInterface;
        curLevel, plotType: integer;
        meshName, explMeshName, edidBase: string;
        exDebris, exChain, exKaboom: IInterface;
    begin
        Result := 0;

        script := getScript(e, 'SimSettlementsV2:Weapons:BuildingLevelPlan');
        if(assigned(script)) then begin
            processLevelPlan(e, script);
            exit;
        end;
        
        script := getScript(e, 'SimSettlementsV2:Weapons:BuildingLevelSkin');
        if(assigned(script)) then begin
            processLevelSkin(e, script);
            exit;
        end;
        
       

    end;

    // Called after processing
    // You can remove it if script doesn't require finalization code
    function Finalize: integer;
    begin
        Result := 0;
        cleanupSS2Lib();
    end;

end.