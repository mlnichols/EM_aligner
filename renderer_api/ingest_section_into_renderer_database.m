function ingest_section_into_renderer_database(mL,rc_target, rc_base, dir_work)
% This is a high-level function that:
% Ingests the data into an existing collection, creates one if the collection doesn't already exist and
% Completes the collection
%
% Since collections are based off of other collections. In this case the base
% collection is specified in the rc_base struct
%
% Author: Khaled Khairy. Janelia Research Campus.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

if ~stack_exists(rc_base), error('base collection not found');end

if ~stack_exists(rc_target) 
    disp('Target collection not found, creating new collection in state: ''Loading''');
    resp = create_renderer_stack(rc_target);
end
if stack_complete(rc_target)
    error('Cannot append COMPLETE stack: switch to LOADING or use ingest_section_into_renderer_database_overwrite to overwrite');
end
%% translate to origin to be Renderer friendly
disp('translating to set in +ve space');
mL = translate_to_origin(mL);

%% export to MET (in preparation to be ingested into the Renderer database
fn = [dir_work '/X_A_' num2str(randi(1000000)) '.txt'];
if strcmp(class(mL.tiles(1).tform), 'images.geotrans.PolynomialTransformation2D')
    export_montage_MET_poly(mL, fn);
    v = 'v3';
else
    export_MET(mL, fn, 2, 2, 0);
    v = 'v1';
end

%% append tiles to existing collection
resp = append_renderer_stack(rc_target, rc_base, fn, v);

%% cleanup
try 
    delete(fn); 
catch err_delete, 
    kk_disp_err(err_delete);
end

%% complete stack
resp = renderer_stack_state_complete(rc_target);
