{
  New script template, only shows processed records
  Assigning any nonzero value to Result will terminate script
}
unit userscript;
    // uses praUtil;

    var
        modelPaths: TStringList;
        modelSearch: TStringList;
        modelReplace: TStringList;

    function loadNifFromArchive(nifPath: string): boolean;
    var
        i: integer;
        containers: TStringList;
        lastContainer: string;
    begin
        containers := TStringList.create;

        // AddMessage('Looking for '+materialName);
        ResourceCount(nifPath, containers);
        for i:=0 to containers.count-1 do begin
            lastContainer := containers[i];
            // AddMessage(containers[i]);
        end;
        containers.free;

        if(lastContainer = '') then begin
            Result := false;
            exit;
        end;

        struct.LoadFromResource(containers, nifPath);

        Result := true;
    end;//ResourceExists

    function doReplace(oldPath: string): string;
    var
        i: integer;
        curKey, curVal, maybeNew: string;
    begin
        Result := '';
        for i:=0 to modelSearch.count-1 do begin
            curKey := modelSearch[i];
            curVal := modelReplace[i];
            maybeNew := StringReplace(oldPath, curKey, curVal, [rfReplaceAll]);
            Addmessage('check '+maybeNew);
            if(ResourceExists('meshes\'+maybeNew)) then begin
                Result := maybeNew;
                exit;
            end;
        end;
    end;
    
    procedure registerReplace(key: string; value: string);
    begin
        modelSearch.add(key);
        modelReplace.add(value);
    end;

    // Called before processing
    // You can remove it if script doesn't require initialization code
    function Initialize: integer;
    begin
        Result := 0;
        modelPaths := TStringList.create;
        modelSearch := TStringList.create;
        modelReplace := TStringList.create;

        modelPaths.add('Model\MODL');
        
        registerReplace('AutoBuildPlots\ResidentialSizeASFHouses\', 'SS2\BuildingPlans\Residential\2x2\');
        registerReplace('AutoBuildPlots\CommercialSizeAArmorStores\', 'SS2\BuildingPlans\Commercial\2x2\ArmorStores\');
		registerReplace('AutoBuildPlots\CommercialSizeABars\', 'SS2\BuildingPlans\Commercial\2x2\Bars\');
		registerReplace('AutoBuildPlots\CommercialSizeAClinics\', 'SS2\BuildingPlans\Commercial\2x2\Clinics\');
		registerReplace('AutoBuildPlots\CommercialSizeAClothingStores\', 'SS2\BuildingPlans\Commercial\2x2\ClothingStores\');
		registerReplace('AutoBuildPlots\CommercialSizeAGeneralStores\', 'SS2\BuildingPlans\Commercial\2x2\GeneralStores\');
		registerReplace('AutoBuildPlots\CommercialSizeAWeaponStores\', 'SS2\BuildingPlans\Commercial\2x2\WeaponStores\');
		
		registerReplace('SS_PBP\Buildings\Commercial\Barber01\', 'SS2\BuildingPlans\Commercial\2x2\BeautySalons\Barber01\');
		registerReplace('SS_PBP\Buildings\Commercial\FurnitureStore01\', 'SS2\BuildingPlans\Commercial\2x2\FurnitureStores\FurnitureStore01\');
		registerReplace('SS_PBP\Buildings\Commercial\PAService01\', 'SS2\BuildingPlans\Commercial\2x2\PowerArmorStores\PAService01\');
		
		registerReplace('SS_IndRev\IndustrialSizeA\', 'SS2\BuildingPlans\Industrial\2x2\BranchingPlans\');
    end;

    // called for every record selected in xEdit
    function Process(e: IInterface): integer;
    var
        sig, curPath, curModel, newModel: string;
        i: integer;
    begin
        Result := 0;

        sig := Signature(e);

        for i:=0 to modelPaths.count-1 do begin
            curPath := modelPaths[i];
            curModel := GetElementEditValues(e, curPath);
            if(curModel = '') then continue;
            
            if(not ResourceExists('meshes\'+curModel)) then begin

                newModel := doReplace(curModel);
                if (newModel <> '') then begin
                    AddMessage('Processing: ' + FullPath(e));
                    SetElementEditValues(e, curPath, newModel);
                end else begin
                    AddMessage('Failed to fix: ' + FullPath(e));
                end;
            end;

        end;

        // comment this out if you don't want those messages

      // processing code goes here

    end;

    // Called after processing
    // You can remove it if script doesn't require finalization code
    function Finalize: integer;
    begin
        Result := 0;
        modelPaths.free();
        modelSearch.free();
        modelReplace.free();
    end;

end.