
%%
function [ntiles_o, ntiles_aff, toc_load_z, time_pm_load, time_gen_A,...
    time_Axb, mean_error_affine, sz_A, nnzA, nnzK, xout] ...
    = timing_loading_solving(sl, z)
nparms = (sl.solver_options.degree + 1) * (sl.solver_options.degree + 2); % twice number of coefficients for a particular polynomial

%% time to load section from Renderer
L = Msection(sl.source_collection, z);
ntiles_o = numel(L.tiles);
tic_load_z = tic;
L = Msection(sl.source_collection, z);
toc_load_z = toc(tic_load_z);
disp(' Time to load tiles and create section object: ');
disp(toc_load_z);
%% time to load point-matches
[L, tIds, PM, pm_mx, sectionId_load, z_load]  = ...
    load_point_matches(...
    sl.z_value,...
    sl.z_value,...
    sl.source_collection, ...
    sl.source_point_match_collection,...
    0,...
    sl.solver_options.min_points,...
    sl.solver_options.xs_weight,...
    sl.solver_options.max_points);

tic_load_pm = tic;

[L, tIds, PM, pm_mx, sectionId_load, z_load, time_pm_load]  = ...
    load_point_matches(...
    sl.z_value,...
    sl.z_value,...
    sl.source_collection, ...
    sl.source_point_match_collection,...
    0,...
    sl.solver_options.min_points,...
    sl.solver_options.xs_weight,...
    sl.solver_options.max_points);

toc_load_pm = toc(tic_load_pm);
disp(' Time to load tiles and create section object: ');
disp(toc_load_pm);

L = add_translation_peggs(L, sl.solver_options.peg_npoints, sl.solver_options.peg_weight);
[L, ntiles] = reduce_to_connected_components(L, sl.solver_options.min_tiles);
L = L(1);
%% solve rigid approximation
sl.solver_options.distributed = 0;
[Lr, errR, mL, is, it, Res, ...
    A, b, B, d, W, K, Lm, xout, L2, U2, tB, td,...
    At, bt, Bt, dt, Wt, Kt, Lmt, xoutt, L2t, U2t, tBt, tdt]  =...
    get_rigid_approximation(L, 'backslash', sl.solver_options);


%%% remove peggs and last tile
last_tile = numel(Lr.tiles);
del_ix = find(Lr.pm.adj(:,2)==last_tile);
Lr.pm.M(del_ix,:)  = [];
Lr.pm.adj(del_ix,:) = [];
Lr.pm.W(del_ix) = [];
Lr.pm.np(del_ix) = [];
Lr.tiles(end) = [];
Lr = update_adjacency(Lr);

%%%%% if calling external C++ solver (using rigid approximation as regularizer)
if strcmp(sl.solver_options.solver, 'jdr')
    dir_scratch = '/groups/flyTEM/home/khairyk/solver_paper_work/scratch';
    delete([dir_scratch '/*.json']);
    disp('calling jdr solver');
    debugjdr = 1;
    lambda = sl.solver_options.lambda;
    degree = sl.solver_options.degree;
    
    if sl.solve_options.jdr_options.stvec==0
        L_jdr = L;
        stvec = 0;
    else
        L_jdr = Lr;
        stvec = 1;   % use fn_canvas_input as input for regularization
        %%% generate json rotation approximation tile-spec file
        fn_canvas_input = ...
            [dir_scratch '/tmp_rap_canvases.json'];
        disp('Generating json rotation approximation tile-spec file ...');
        tic;jstr_rap = export_json(L_jdr, fn_canvas_input);toc;
    end
    
    fnpmjson = ...
        [dir_scratch '/tmp_pm.json'];
    disp('Generating json point-match file ...');
    tic;jstr = PM_json(L_jdr, fnpmjson);toc;
    
    disp('Done');
    
    
    if debugjdr
        type(fn_canvas_input);
    end
    
    disp('Done');
    
    %%% sosi
    %fnpmjson ='/groups/flyTEM/home/khairyk/downloads/JDR/example01_pm.json';
    
    time_Axb = -999;
    time_gen_A = -999;
    % % call cpp solver program
    % clc;
    disp('-------------------- Invoking cpp solver --------------');
    kk_clock;
    fn_canvas_json_output = ...
        [dir_scratch '/canvases_out.json'];
    solv_cmd = '/groups/flyTEM/home/khairyk/downloads/jdr/joint-image-registration-solver/jdr_solver';
    
    
    cmd = [solv_cmd ' ' fnpmjson ' ' fn_canvas_json_output ' ' num2str(degree) ...
        ' ' num2str(lambda) ' ' num2str(stvec) ' ' fn_canvas_input];
    tic;[a,resp_str] = system(cmd);toc
    
    if debugjdr
        disp(resp_str);
        disp(fn_canvas_json_output);
        type(fn_canvas_json_output);
    end
    
    
    
    
    C = strsplit(resp_str, 'TIME_');
    c = strsplit(C{2}, ' ');
    time_gen_A = str2double(c{2});
    c = strsplit(C{3}, ' ');
    time_Axb = str2double(c{2});
    disp('finished cpp solution');
    kk_clock;
    %disp(resp_str);
    mLjdr = update_transformation_from_json(Lr,fn_canvas_json_output);
    
    %%% to continue diagnostics we need to set to matrix_only
    sld = sl;
    sld.solver_options.matrix_only = 1;
    [mL, err1, Res1, A, b, B, d, W, K, Lm, xout, LL2, U2, tB, td,...
        invalid] = solve_affine_explicit_region(mLjdr,...
        sld.solver_options);
    
else
    
    
    %% point-match erros and point-match tile-based errors
    % r_res = At * xoutt;
    % [Lrc, tpr] = tile_based_point_pair_errors(Lr, At, xoutt);
    %% solve affine
    [mL, err1, Res1, A, b, B, d, W, K, Lm, xout, LL2, U2, tB, td,...
        invalid, time_Axb, time_gen_A] = solve_affine_explicit_region(Lr, sl.solver_options);
    
end
nnzK = nnz(K);
nnzA = nnz(A);
disp('time constructing linear system');
disp(time_gen_A);
disp('time solving A x = b');
disp(time_Axb);
%% point-match erros and point-match tile-based errors
% a_res = A * xout;
[mLc, tpr, resout] = tile_based_point_pair_errors(mL, A, xout);
mean_error_affine = mean(resout);
ntiles_aff = size(K,1)/nparms; %numel(resout);%sum([mLc.tiles(:).state]);
disp(ntiles_aff);
disp(mean_error_affine);
sz_A = size(A);
% figure(1);hist(a_res);
% figure(2); hist(resout);
%disp(resout);
%% regularization parameter sweep
% [L, L_vec, pm_mx, err, scl, h, toc_load_pm, toc_rigid] = ...
%     solver_regularization_parameter_sweep(...
%     nfirst, nlast,...
%     rcsource, pm, opts, regstart, regfinish, step);

end

