% The script assumes the existence of a Renderer collection (configured below)
% Dependencies:
%               - Renderer service
%               - script to generate spark_montage_scapes
%
% Calculate the full stitching (montage and alignment) of a set of sections
% Ingest this slab into a new collection
%
% Author: Khaled Khairy
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%% [0] configure collections and prepare quantities
clc;
% nfirst = 1245;
% nlast  = 1247;

nfirst = 1;
nlast  = 4;

% configure source collection
rcsource.stack          = 'v12_acquire_merged';
rcsource.owner          ='flyTEM';
rcsource.project        = 'FAFB00';
rcsource.service_host   = '10.37.5.60:8080';
rcsource.baseURL        = ['http://' rcsource.service_host '/render-ws/v1'];
rcsource.verbose        = 1;

% configure montage collection

rctarget_montage.stack          = ['EXP_v12_SURF_montage_' num2str(nfirst) '_' num2str(nlast)];
rctarget_montage.owner          ='flyTEM';
rctarget_montage.project        = 'test';
rctarget_montage.service_host   = '10.37.5.60:8080';
rctarget_montage.baseURL        = ['http://' rctarget_montage.service_host '/render-ws/v1'];
rctarget_montage.verbose        = 1;

% configure rough collection
rctarget_rough.stack          = ['EXP_v12_SURF_rough_' num2str(nfirst) '_' num2str(nlast)];
rctarget_rough.owner          ='flyTEM';
rctarget_rough.project        = 'test';
rctarget_rough.service_host   = '10.37.5.60:8080';
rctarget_rough.baseURL        = ['http://' rctarget_rough.service_host '/render-ws/v1'];
rctarget_rough.verbose        = 1;

% configure align collection
rctarget_align.stack          = ['EXP_v12_SURF_align_' num2str(nfirst) '_' num2str(nlast)];
rctarget_align.owner          = 'flyTEM';
rctarget_align.project        = 'test';
rctarget_align.service_host   = '10.37.5.60:8080';
rctarget_align.baseURL        = ['http://' rctarget_rough.service_host '/render-ws/v1'];
rctarget_align.verbose        = 1;

% configure point-match collection
pm.server           = 'http://10.40.3.162:8080/render-ws/v1';
pm.owner            = 'flyTEM';
pm.match_collection = 'v12_SURF';

% configure montage-scape point-match generation
ms.service_host                 = rctarget_montage.service_host;
ms.owner                        = rctarget_montage.owner;
ms.project                      = rctarget_montage.project;
ms.stack                        = rctarget_montage.stack;
ms.first                        = num2str(nfirst);
ms.last                         = num2str(nlast);
ms.fd_size                      = '8';
ms.min_sift_scale               = '0.55';
ms.max_sift_scale               = '1.0';
ms.steps                        = '3';
ms.scale                        = '0.15';    % normally less than 0.05 -- can be large (e.g. 0.2) for very small sections (<100 tiles)
ms.similarity_range             = '3';
ms.skip_similarity_matrix       = 'y';
ms.skip_aligned_image_generation= 'y';
ms.base_output_dir              = '/nobackup/flyTEM/spark_montage';
ms.run_dir                      = ['scale_' ms.scale];
ms.script                       = '/groups/flyTEM/home/khairyk/EM_aligner/external/generate_montage_scape_point_matches.sh';%'../unit_tests/generate_montage_scape_point_matches_stub.sh'; %

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% get the list of zvalues and section ids within the z range between nfirst and nlast (inclusive)
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
urlChar = sprintf('%s/owner/%s/project/%s/stack/%s/sectionData', ...
    rcsource.baseURL, rcsource.owner, rcsource.project, rcsource.stack);
j = webread(urlChar);
sectionId = {j(:).sectionId};
z         = [j(:).z];
indx = find(z>=nfirst & z<=nlast);

sectionId = sectionId(indx);% determine the sectionId list we will work with
z         = z(indx);        % determine the zvalues (this is also the spatial order)
%% [1] generate montage for individual sections and generate montage collection
L = Msection;
L(numel(z)) = Msection;
for lix = 1:numel(z)
    L(lix)                  = Msection(rcsource, z(lix));  % tiles will have stage translations and when requested provide LC images.
    L(lix).dthresh_factor   = 3;
    L(lix)                  = update_XY(L(lix));
    L(lix)                  = update_adjacency(L(lix));
    [L(lix), js]            = alignTEM_inlayer(L(lix));
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    %%% ingest js into point matches database
    %%% this needs to be done using webwrite --- sosi ---  until then <sigh> we will use curl
    fn = ['temp_' num2str(randi(100000)) '_' num2str(lix) '.json'];
    fid = fopen(fn, 'w');
    fwrite(fid,js);
    fclose(fid);
    urlChar = sprintf('%s/owner/%s/matchCollection/%s/matches/', ...
        pm.server, pm.owner, pm.match_collection);
    cmd = sprintf('curl -X PUT --connect-timeout 30 --header "Content-Type: application/json" --header "Accept: application/json" -d "@%s" "%s"',...
        fn, urlChar);
    [a, resp]= evalc('system(cmd)');
    delete(fn);
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
end
opts.outlier_lambda = 1e3;  % large numbers result in fewer tiles excluded
mL = concatenate_tiles(L, opts.outlier_lambda);

ingest_section_into_renderer_database_overwrite(mL, rctarget_montage, rcsource, pwd);
mL = update_tile_sources(mL, rctarget_montage);
L_montaged = split_z(mL);

%% [2] generate montage-scapes and montage-scape point-matches

[L2] = generate_montage_scapes_SIFT_point_matches(ms);

% %% filter point matches using RANSAC
geoTransformEst = vision.GeometricTransformEstimator; % defaults to RANSAC
geoTransformEst.Method = 'Random Sample Consensus (RANSAC)';%'Least Median of Squares';
geoTransformEst.Transform = 'Affine';%'Nonreflective similarity';%'Affine';%
geoTransformEst.NumRandomSamplingsMethod = 'Desired confidence';
geoTransformEst.MaximumRandomSamples = 1000;
geoTransformEst.DesiredConfidence = 99.95;
for pmix = 1:size(L2.pm.M,1)
    m1 = L2.pm.M{pmix,1};
    m2 = L2.pm.M{pmix,2};
    % Invoke the step() method on the geoTransformEst object to compute the
    % transformation from the |distorted| to the |original| image. You
    % may see varying results of the transformation matrix computation because
    % of the random sampling employed by the RANSAC algorithm.
    [tform_matrix, inlierIdx] = step(geoTransformEst, m2, m1);
    m1 = m1(inlierIdx,:);
    m2 = m2(inlierIdx,:);
    L2.pm.M{pmix,1} = m1;
    L2.pm.M{pmix,2} = m2;
    w = L2.pm.W{pmix};
    L2.pm.W{pmix} = w(inlierIdx);
end
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% % check point match quality
% for lix = 1%:size(L2.pm.adj,1)
%     ix1 = L2.pm.adj(lix,1);
%     ix2 = L2.pm.adj(lix,2);
%     t1 = L2.tiles(ix1);
%     t2 = L2.tiles(ix2);
%     M = L2.pm.M(lix,:);
%     show_feature_point_correspondence(t1,t2,M);title([num2str(ix1) '   ' num2str(ix2)]);
%     drawnow;
% end
%% [3] rough alignment solve for montage-scapes

% solve
[mLR, errR, mLS] = get_rigid_approximation(L2);  % generate rigid approximation to use as regularizer
[mL3, errA] = solve_affine_explicit_region(mLR); % obtain an affine solution
mL3s = split_z(mL3);
%% [4] apply rough alignment to montaged sections (L_montaged) and generate "rough_aligned" collection  %% %%%%%% sosi
for lix = 1:numel(L_montaged), L_montaged(lix) = get_bounding_box(L_montaged(lix));end
mL3 = get_bounding_box(mL3);
Wbox = [mL3.box(1) mL3.box(3) mL3.box(2)-mL3.box(1) mL3.box(4)-mL3.box(3)];disp(Wbox);
wb1 = Wbox(1);
wb2 = Wbox(2);
L3 = L_montaged;
fac = str2double(ms.scale); %0.25;

smx = [fac 0 0; 0 fac 0; 0 0 1]; %scale matrix
invsmx = [1/fac 0 0; 0 1/fac 0; 0 0 1];
tmx2 = [1 0 0; 0 1 0; -wb1 -wb2 1]; % translation matrix for montage_scape stack

for lix = 1:numel(L_montaged)
    b1 = L_montaged(1).box;
    dx = b1(1);dy = b1(3);
    tmx1 = [1 0 0; 0 1 0; -dx -dy 1];  % translation matrix for section box
    for tix = 1:numel(L3(lix).tiles)
        newT = L3(lix).tiles(tix).tform.T * tmx1 * smx * mL3s(lix).tiles(1).tform.T * tmx2 * (invsmx);
        L3(lix).tiles(tix).tform.T = newT;
    end
    L3(lix) = update_XY(L3(lix));
end
opts.outlier_lambda = 1e3;  % large numbers result in fewer tiles excluded
mL = concatenate_tiles(L3, opts.outlier_lambda);
ingest_section_into_renderer_database_overwrite(mL,rctarget_rough, rcsource, pwd);
mL = update_tile_sources(mL, rctarget_rough);
L_rough = split_z(mL);
for lix = 1:numel(L_rough), L_rough(lix) = update_XY(L_rough(lix));end
%% [5] Determine list of section pairs that will be compared
% first determine the list of section pairs
dthresh_factor = 1; % factor multiplied by tile diagonal to determine radius of inclusion of potential tile-tile overlap partners
depth = 1;  % largest distance (in layers) considered for neighbors
top = numel(L_rough);
bottom = 1;
cs = [];  % compare section list
counter = 1;
for uix = top:-1:bottom
    lowest = uix-depth;
    if lowest<bottom, lowest = bottom;end
    for vix = uix:-1:lowest
        if vix<uix
            cs(counter,:) = [uix vix];
            counter = counter + 1;
        end
    end
end
disp(cs);
%% [6] Determine blocks to match
DX = 4;   % number of divisions of the total bounding box in x
DY = 4;
dir_temp_render = L_rough(1).tiles(1).dir_temp_render;
Wbox = zeros(numel(L_rough), 4);
bbox = zeros(numel(L_rough),4);
parfor lix = 1:numel(L_rough)
    [ Wbox(lix,:), bbox(lix,:)] = get_section_bounds_renderer(rctarget_rough, z(lix));
end
% sosi---- im = get_image_box_renderer(rc, t.z, Wbox, 0.1, dir_temp_render, 'rough_block'); imshow(im);
bb = [min(Wbox(:,1)) min(Wbox(2)) max(bbox(:,3)) max(bbox(:,4))];
wb = [bb(1) bb(2) bb(3)-bb(1) bb(4)-bb(2)];

% draw rectangles

%rectangle('Position', wb, 'FaceColor', [0.5 0.5 0.5]);
dx = round(wb(3)/DX);
dy = round(wb(4)/DY);

wbox = zeros(DX*DY, 4);
counter = 1;
for xix = 0:DX-1
    for yix = 0:DY-1
        xpos = bb(1)+xix*dx;
        ypos = bb(2)+yix*dy;
        wbox(counter,:) = [ xpos  ypos dx dy];
        counter = counter + 1;
        %rcolor = rand(1,3);rectangle('Position', wbox, 'FaceColor', rcolor);  pause(1);
    end
end

% list sections and block windows in preparation for parfor
b = zeros(DX*DY,6);
count = 1;
for cix = 1:size(cs,1)    % loop over section pairs
    for bix = 1:size(wbox,1)  % loop over blocks
        b(count,:) = [cs(cix,:) wbox(bix,:)];
        count = count + 1;
    end
end

% get montage boxes as well
Wboxm = zeros(numel(L_montaged), 4);
bboxm = zeros(numel(L_montaged),4);
parfor lix = 1:numel(L_montaged)
    [ Wboxm(lix,:), bboxm(lix,:)] = get_section_bounds_renderer(rctarget_montage, z(lix));
end
bbm = [min(Wboxm(:,1)) min(Wboxm(2)) max(bboxm(:,3)) max(bboxm(:,4))];
wbm = [bbm(1) bbm(2) bbm(3)-bbm(1) bbm(4)-bbm(2)];

%% [7] generate point-matches for all blocks   --- needs to be "parfor"d
scale = 0.15;
parfor bix = 1:size(b,1)   % process each line in b (a section pair and block window -- x y W H)
    ids = {};
    pairs = [];
    w = [];
    count = 1;
    disp(bix);
    box = b(bix, 3:6);
    %%% use SIFT
    url1 = sprintf('%s/owner/%s/project/%s/stack/%s/z/%s/box/%.0f,%.0f,%.0f,%.0f,%s/render-parameters?filter=true',...
        rctarget_rough.baseURL, rctarget_rough.owner, rctarget_rough.project, rctarget_rough.stack, num2str(b(bix,1)), ...
        box(1), ...
        box(2), ...
        box(3), ...
        box(4), ...
        num2str(scale));
    url2 = sprintf('%s/owner/%s/project/%s/stack/%s/z/%s/box/%.0f,%.0f,%.0f,%.0f,%s/render-parameters?filter=true',...
        rctarget_rough.baseURL, rctarget_rough.owner, rctarget_rough.project, rctarget_rough.stack, num2str(b(bix,2)), ...
        box(1), ...
        box(2), ...
        box(3), ...
        box(4), ...
        num2str(scale));
    
    [m_2, m_1, js] = point_match_gen_SIFT_qsub(url2, url1);   % submits jobs -- returns point-matches in box coordinate system%%% production --- submit to cluster
    %[m_2, m_1] = point_match_gen_SIFT(url2, url1);
    if ~isempty(m_1),
        
        %%% SOSI == look at images and point matches
        %         [im1, v1] = get_image_box_renderer(rctarget_rough, b(bix,1), box, scale, dir_temp_render, num2str(b(bix,1)));
        %         [im2, v2] = get_image_box_renderer(rctarget_rough, b(bix,2), box, scale, dir_temp_render, num2str(b(bix,2)));
        %         clf;warning off;imshowpair(im1, im2, 'montage'); title(num2str(bix));drawnow
        %         if ~isempty(m12_1), figure; warning off;showMatchedFeatures(im1, im2, m_1, m_2, 'montage');end
        
        % convert these point-matches to "acquire or montage" coordinate system to make them ingestable json strings that will go into pm collection
        for pimix = 1:numel(m_1,1)   % loop over box point-matches
            % Strategy: for each set of point we convert from world to (rough-aligned) local
            % What we really want is local "acquire", so we need to convert from (rough-aligned) local to
            % acquire world,
            % then subtract translation component of tile specs from points so that they become
            % (acquire) local
            
            %%%%%%%%%%%
            % first convert point found in the first box (in layer(b(bix,1)))
            %%%%%%%%%%%%
            x = m_1(1,1)/scale + box(1);
            y = m_1(1,2)/scale + box(2);
            z1 = b(bix,1);
            [pGroupId, p] = world_to_local_LC_tile(rctarget_rough, rctarget_montage, [x y z1], wbm);
            %%%%%%%%%%%
            % second convert point found in the second box (in layer(b(bix,2)))
            %%%%%%%%%%%%
            x = m_2(1,1)/scale + box(1);
            y = m_2(1,2)/scale + box(2);
            z2 = b(bix,2);
            [qGroupId, q] = world_to_local_LC_tile(rctarget_rough, rctarget_montage, [x y z2], wbm);
            
            % write into buffer
            ids{count,1} = pGroupId;
            ids{count,2} = qGroupId;
            pairs(count,:) = [p q];
            w(count) =1/(1 + abs(z1-z2));
            count = count + 1;
        end
    end
    IDS(bix)    = {ids};
    PAIRS(bix)  = {pairs};
    W(bix)      = {w};
end
%% [8] Convert block point-matches into tile-tile point-matches


%% [9] ingest into pm database

%% [10] Solve system



%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% [5] Determine potential tile partners crosslayer (determine the list of cross-layer tile partners)
% % first determine the list of section pairs
% dthresh_factor = 1; % factor multiplied by tile diagonal to determine radius of inclusion of potential tile-tile overlap partners
% depth = 1;  % largest distance (in layers) considered for neighbors
% top = numel(L_rough);
% bottom = 1;
% cs = [];  % compare section list
% counter = 1;
% for uix = top:-1:bottom
%     lowest = uix-depth;
%     if lowest<bottom, lowest = bottom;end
%     for vix = uix:-1:lowest
%         if vix<uix
%             cs(counter,:) = [uix vix];
%             counter = counter + 1;
%         end
%     end
% end
% disp(cs);
%
% % loop over cs pairs and determine potential tile pairs
% l1 = [];
% l2 = [];
% id1 = [];
% id2 = [];
% rid1 = {};
% rid2 = {};
% H = L3(1).tiles(1).H;
% W = L3(1).tiles(1).W;
% for dix = 1:size(cs,1)
%     lix1 = cs(dix,1);
%     lix2 = cs(dix,2);
%     a = [L_rough(lix1).X L_rough(lix1).Y];
%     b = [L_rough(lix2).X L_rough(lix2).Y];
%     d = pdist2(a,b);        % depends on statistics toolbox  -------- Sosi: not good for large numbers of tiles
%     dthresh = sqrt(H^2 + W^2) * dthresh_factor;   % diagonal of the tile times factor
%     A = sparse(triu(d<dthresh,0)); % generate adjacency matrix
%     [r c] = ind2sub(size(A), find(A));
%     l1 = [l1 lix1 * ones(1,size(r(:),1))];
%     l2 = [l2 lix2 * ones(1,size(c(:),1))];
%     id1 = [id1 r(:)'];
%     id2 = [id2 c(:)'];
%     rid1 = [rid1 {L_rough(lix1).tiles(r).renderer_id}];
%     rid2 = [rid2 {L_rough(lix2).tiles(c).renderer_id}];
% end
% %% [6] fine alignment (cross-layer point-matches)
% minpm = 3;
% M = cell(numel(id1),2);
% adj = zeros(numel(id1),2);
% W = cell(numel(id1),1);
% np = zeros(numel(id1),1);
% delpix = zeros(numel(id1),1, 'uint32');
% %parfor_progress(numel(id1));
% parfor pix = 1: numel(id1)
%     disp([pix l1(pix) l2(pix) id1(pix) id2(pix)]);
%     %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%     t1 = L(l1(pix)).tiles(id1(pix));
%     t2 = L(l2(pix)).tiles(id2(pix));
%     t1.fetch_local = 0;
%     t2.fetch_local = 0;
%
%     im1 = get_image(t1);
%     im2 = get_image(t2);
%     im1r = rangefilt(im1);
%     im2r = rangefilt(im2);
%     figure;imshowpair(im1, im2, 'montage');
%     figure;imshowpair(im1r, im2r, 'montage');
%
%
%     [m12_1, m12_2, js] = point_match_gen_SIFT(t1, t2);
%
%     %[m1, m2, w, imt1] = kk_dftregistration(im1, im2);
%
%     %%%%%% sosi
% %      figure; showMatchedFeatures(im1, im2, m1, m2, 'montage');
% %      figure;imshowpair(im1, imt1, 'montage');
%
%     %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%
%     M(pix,:) = {[m1],[m2]};
%
%
%     %%%%%%%% sosi
% %     show_feature_point_correspondence(t1,t2,M(pix,:));
%     %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%
%     adj(pix,:) = [id1(pix) id2(pix)];
%     W(pix) = {[ones(size(m1,1),1) * 1/(1+ abs(L3(l1(pix)).tiles(id1(pix)).z-L3(l2(pix)).tiles(id2(pix)).z))]};
%     np(pix)  = size(m1,1);
%     %%%% mark for removal point-matches that don't have enough point pairs
%     if size(m1,1)<minpm
%         delpix(pix) = 1;
%     end
% %    parfor_progress;
% end
% %parfor_progress(0);
% if isempty(M), error('No matches found');end;
% disp('Done!');
%
%
% delpix = logical(delpix);
% M(delpix,:) = [];
% adj(delpix,:) = [];
% W(delpix) = [];
% np(delpix) = [];
%
% l1(delpix) = [];
% l2(delpix) = [];
% id1(delpix) = [];
% id2(delpix) = [];
% rid1(delpix) = [];
% rid2(delpix) = [];
%
%
% pm.M = M;
% pm.adj = adj;
% pm.W = W;
% pm.np = np;
%
% %%%%%%%%%% sosi
% % %% check  point matches
% warning off;
% for lix = 1:size(pm.adj,1)
%     ix1 = pm.adj(lix,1);
%     ix2 = pm.adj(lix,2);
%     t1 = L(l1(lix)).tiles(ix1);
%     t2 = L(l2(lix)).tiles(ix2);
%     M = pm.M(lix,:);
%     str = [num2str(size(pm.M{lix,1},1)), 'Section: ' t1.sectionId ' tile: ' num2str(ix1) '   ' 'Section: ' t2.sectionId ' tile: ' num2str(ix2)];
%     close all;    show_feature_point_correspondence(t1,t2,M);
%     title(str);    %truesize(gcf, [1000 1000]);
%     drawnow;pause(3);
% disp(str);
% end
% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% %% [7] transform point matches to lens-corrected-only stage and ingest into pm database
% for pix = 1:size(pm.adj,1)
%     t1 = L3(l1(pix)).tiles(id1(pix));
%     t2 = L3(l2(pix)).tiles(id2(pix));
%     pm1 = [pm.M{pix,1} ones(size(pm.M{pix,1},1),1)] * inv(t1.tform.T);
%     pm2 = [pm.M{pix,2} ones(size(pm.M{pix,2},1),1)] * inv(t2.tform.T);
%
%     pm.M{pix,1} = pm1(:,1:2);
%     pm.M{pix,2} = pm2(:,1:2);
% end
% % generate json point-match data
% counter = 1;
% M = pm.M;
% adj = pm.adj;
% for mix = 1:size(M,1)
%     indx1 = adj(mix,1);
%     indx2 = adj(mix,2);
%     tid1 = [L3(l1(mix)).tiles(indx1).renderer_id];
%     tid2 = [L3(l2(mix)).tiles(indx2).renderer_id];
%
%     MP{counter}.pz = L3(l1(mix)).tiles(indx1).sectionID;
%     MP{counter}.pId= tid1;
%     MP{counter}.p  = M{mix,1};
%
%     MP{counter}.qz = L3(l2(mix)).tiles(indx2).sectionID;
%     MP{counter}.qId= tid2;
%     MP{counter}.q  = M{mix,2};
%     counter = counter + 1;
% end
% js = pairs2json(MP); % generate json blob to be ingested into point-match database
% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% %%% ingest js into point matches database
% fn = ['temp_' num2str(randi(100000)) '_' num2str(lix) '.json'];
% fid = fopen(fn, 'w');
% fwrite(fid,js);
% fclose(fid);
% urlChar = sprintf('%s/owner/%s/matchCollection/%s/matches/', ...
%     pm.server, pm.owner, pm.match_collection);
% cmd = sprintf('curl -X PUT --connect-timeout 30 --header "Content-Type: application/json" --header "Accept: application/json" -d "@%s" "%s"',...
%     fn, urlChar);
% [a, resp]= evalc('system(cmd)');
% delete(fn);
% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%
%% [8] solve whole system

%% [9] generate the new collection







































