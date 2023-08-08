{
    Replace a script name
}
unit userscript;
    uses 'SS2\praUtilSS2';

    var
        propSearch, propReplace: string;
        
        scriptListSearch, scriptListReplace: TStringList;
        
    procedure registerReplacement(s: string; r: string);
    begin
        scriptListSearch.add(s);
        scriptListReplace.add(r);
    end;

    // Called before processing
    // You can remove it if script doesn't require initialization code
    function Initialize: integer;
    begin
        Result := 0;
        
        scriptListSearch := TStringList.create;
        scriptListReplace:= TStringList.create;
        {
        registerReplacement('praSim:HolotapeDummyScript', 'praSS2:HolotapeDummyScript');
        

        // other crap
        registerReplacement('praSim:AutoLinkingWorkbenchScript', 'praSS2:SoftReqWorkbench');


        registerReplacement('praSim:PiratedArcadeTerminal', 'praSS2:PiratedArcadeScript');

        registerReplacement('praSim:VaultExerciseFurniture', 'praSS2:VaultExerciseFurniture');

        registerReplacement('praSim:PlotSubSpawnerMultistage', 'praSS2:PlotSubSpawnerMultistage');

        registerReplacement('praSim:PlotSubSpawner', 'praSS2:PlotSubSpawnerMultistage');

        registerReplacement('praSim:ConditionSpawner', 'praSS2:ConditionSpawner');

        registerReplacement('praSim:ConditionSpawnerMultistage', 'praSS2:ConditionSpawner');

        registerReplacement('praSim:PoweredObjectSpawner', 'praSS2:PoweredObjectSpawner');

        registerReplacement('praSim:PoweredObjectSpawnerMultistage', 'praSS2:PoweredObjectSpawner');

        registerReplacement('praSim:HolotapeCopyTerminal', 'praSS2:HolotapeCopyTerminal');

        registerReplacement('praSim:PlotCellEntranceDoor', 'praSS2:PlotCellEntranceDoor');

        registerReplacement('praSim:CeilingTurretScript', 'praSS2:CeilingTurretScript');
        registerReplacement('praSim:WallTurretScript', 'praSS2:WallTurretScript');

        registerReplacement('praSim:DiscoveryNote', 'praSS2:DiscoveryNote');

        registerReplacement('praSim:PirateCompatUpdater', 'praSS2:PirateCompatUpdater');

        registerReplacement('praSim:PlotActorSpawner', 'praSS2:PlotActorSpawner');
        
        registerReplacement('praSim:PlotCellExitDoor', 'praSS2:PlotCellExitDoor');
        
        registerReplacement('praSim:SwitchingPlotCellExitDoor', 'praSS2:SwitchingPlotCellExitDoor');        
        registerReplacement('praSim:PlotCellEntranceDoor', 'praSS2:PlotCellEntranceDoor');
        }
        registerReplacement('pra:OdditySpawner', 'praSS2:OdditySpawner');

        propSearch  := 'praSim_AddonQuest';
        propReplace := 'praSS2_AddonQuest';
    end;

    procedure processProp(script: IInterface);
    var
        prop: IInterface;
    begin
        if(propSearch = '') then exit;

        prop := getRawScriptProp(script, propSearch);
        if(not assigned(prop)) then begin
            exit;
        end;

        SetElementEditValues(prop, 'propertyName', propReplace);
    end;


    // called for every record selected in xEdit
    function Process(e: IInterface): integer;
    var
        script: IInterface;
        i: integer;
        scriptSearch, scriptReplace: string;
    begin
        Result := 0;
        
// AddMessage('FUCK '+IntToStr(scriptListSearch.count));
        for i:=0 to scriptListSearch.count-1 do begin
        
            scriptSearch := scriptListSearch[i];
            scriptReplace:= scriptListReplace[i];
// AddMessage('Checking '+scriptSearch);
            script := getScript(e, scriptSearch);
            if(not assigned(script)) then begin
                script := getScript(e, scriptReplace);
                if(assigned(script)) then begin
                    processProp(script);
                end;
                continue;
            end;

            AddMessage('Processing: ' + FullPath(e));

            SetElementEditValues(script, 'ScriptName', scriptReplace);
            processProp(script);
        end;
    end;

    // Called after processing
    // You can remove it if script doesn't require finalization code
    function Finalize: integer;
    begin
        Result := 0;
        
        scriptListSearch.free();
        scriptListReplace.free();
    end;

end.