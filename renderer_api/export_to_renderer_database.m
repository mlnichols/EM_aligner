function export_to_renderer_database(rc_target, rc, dir_scratch, ...
    Tout, tIds, z_val, v, disableValidation)
% v = 'v1' for affines and 'v3' for polynomials higher than one.
if nargin<8, disableValidation = 0;end
fn = [dir_scratch '/X_A_' num2str(randi(100000000)) '.txt'];
if size(Tout,2)==6
    %%% fast export for affines only
    %disp('Exporting temporary MET file');
    
    fid = fopen(fn,'w');
    for tix = 1:size(Tout,1)
        fprintf(fid,'%d\t%s\t%d\t%.12f\t%.12f\t%.12f\t%.12f\t%.12f\t%.12f\t%d\t%d\t%d\t%s\t%d\n',...
            z_val(tix),...
            tIds{tix}, ...  %%L.tiles(tix).renderer_id, ... %
            1, ...
            Tout(tix,1), ...
            Tout(tix,2), ...
            Tout(tix,3), ...
            Tout(tix,4), ...
            Tout(tix,5), ...
            Tout(tix,6), ...
            999, ...
            999, ...
            999, ...
            'nan',...
            999);
    end
    fclose(fid);
    
elseif size(Tout,2)==12
    err = 0;
    fid = fopen(fn,'w');
    for tix = 1:size(Tout,1)

                    fprintf(fid,'%d\t%s\t%d\t%.12f\t%.12f\t%.12f\t%.12f\t%.12f\t%.12f\t%.12f\t%.12f\t%.12f\t%.12f\t%.12f\t%.12f\n',...
                        z_val.z,...
                        tIds{tix}, ...
                        12, ...
                        ...
                        Tout(tix,1), ...
                        Tout(tix,2), ...
                        Tout(tix,3), ...
                        Tout(tix,4), ...
                        Tout(tix,5), ...
                        Tout(tix,6), ...
                        ...
                        Tout(tix,7), ...
                        Tout(tix,8), ...
                        Tout(tix,9), ...
                        Tout(tix,10), ...
                        Tout(tix,11), ...
                        Tout(tix,12));
%                 elseif mL.tiles(tix).tform.Degree==3
%                     fprintf(fid,'%d\t%s\t%d\t%.12f\t%.12f\t%.12f\t%.12f\t%.12f\t%.12f\t%.12f\t%.12f\t%.12f\t%.12f\t%.12f\t%.12f\t%.12f\t%.12f\t%.12f\t%.12f\t%.12f\t%.12f\t%.12f\t%.12f\n',...
%                         mL.tiles(tix).z,...
%                         mL.tiles(tix).renderer_id, ...
%                         20, ...
%                         ...
%                         mL.tiles(tix).tform.A(1), ...
%                         mL.tiles(tix).tform.A(2), ...
%                         mL.tiles(tix).tform.A(3), ...
%                         mL.tiles(tix).tform.A(5), ...
%                         mL.tiles(tix).tform.A(4), ...
%                         mL.tiles(tix).tform.A(6), ...
%                         mL.tiles(tix).tform.A(9), ...    % x^3
%                         mL.tiles(tix).tform.A(7), ...    % x^2 y
%                         mL.tiles(tix).tform.A(8), ...    % x   y^2
%                         mL.tiles(tix).tform.A(10), ...   %     y^3
%                         ...
%                         mL.tiles(tix).tform.B(1), ...
%                         mL.tiles(tix).tform.B(2), ...
%                         mL.tiles(tix).tform.B(3), ...
%                         mL.tiles(tix).tform.B(5), ...
%                         mL.tiles(tix).tform.B(4), ...
%                         mL.tiles(tix).tform.B(6), ...
%                         mL.tiles(tix).tform.B(9), ...    % x^3
%                         mL.tiles(tix).tform.B(7), ...
%                         mL.tiles(tix).tform.B(8), ...
%                         mL.tiles(tix).tform.B(10));

    end
    fclose(fid);
    
end
%% append tiles to existing collection
%disp(' ..... appending data to collection....');
set_renderer_stack_state_loading(rc_target);
resp_append = append_renderer_stack(rc_target, rc, fn, v, disableValidation);
%% cleanup
%disp(' .... cleanup..');
try
    %%delete(fn);
catch err_delete,
    kk_disp_err(err_delete);
end