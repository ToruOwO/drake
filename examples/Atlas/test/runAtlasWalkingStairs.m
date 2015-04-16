function runAtlasWalkingStairs()
% Climb a set of stairs modeled after the DRC finals task

checkDependency('iris');
checkDependency('lcmgl');
path_handle = addpathTemporary(fullfile(getDrakePath(), 'examples', 'Atlas'));

robot_options = struct();
robot_options = applyDefaults(robot_options, struct('use_bullet', true,...
                                                    'terrain', RigidBodyFlatTerrain,...
                                                    'floating', true,...
                                                    'ignore_self_collisions', true,...
                                                    'ignore_effort_limits', true,...
                                                    'enable_fastqp', true,...
                                                    'ignore_friction', true,...
                                                    'use_new_kinsol', true,...
                                                    'hand_right', 'robotiq_weight_only',...
                                                    'hand_left', 'robotiq_weight_only',...
                                                    'dt', 0.001));
% silence some warnings
warning('off','Drake:RigidBodyManipulator:UnsupportedContactPoints')
warning('off','Drake:RigidBodyManipulator:UnsupportedVelocityLimits')

% construct robot model
r = Atlas(fullfile(getDrakePath,'examples','Atlas','urdf','atlas_minimal_contact.urdf'),robot_options);
r = r.removeCollisionGroupsExcept({'heel','toe'});
r = compile(r);

% set initial state to fixed point
load(fullfile(getDrakePath,'examples','Atlas','data','atlas_fp.mat'));

xstar(r.findPositionIndices('r_arm_usy')) = -0.931;
xstar(r.findPositionIndices('r_arm_shx')) = 0.717;
xstar(r.findPositionIndices('r_arm_ely')) = 1.332;
xstar(r.findPositionIndices('r_arm_elx')) = -0.871;
xstar(r.findPositionIndices('l_arm_usy')) = -0.931;
xstar(r.findPositionIndices('l_arm_shx')) = -0.717;
xstar(r.findPositionIndices('l_arm_ely')) = 1.332;
xstar(r.findPositionIndices('l_arm_elx')) = 0.871;
xstar = r.resolveConstraints(xstar);

r = r.setInitialState(xstar);
x0 = xstar;
nq = r.getNumPositions();

box_size = [0.28, 39*0.0254, 0.22];

box_tops = [0.2, 0, 0;
            0.2+0.28, 0, 0.22;
            0.2+2*0.28, 0, 0.22*2;
            0.2+3*0.28, 0, 0.22*3;
            0.2+4*0.28, 0, 0.22*4]';

safe_regions = iris.TerrainRegion.empty();

for j = 1:size(box_tops, 2)
  b = RigidBodyBox(box_size, box_tops(:,j) + [0;0;-box_size(3)/2], [0;0;0]);
  r = r.addGeometryToBody('world', b);
  [A, b] = poly2lincon(box_tops(1,j) + [-0.01, 0, 0, -0.01],...
                       box_tops(2,j) + [-0.25, -0.25, 0.25, 0.25]);
  [A, b] = convert_to_cspace(A, b);
  safe_regions(end+1) = iris.TerrainRegion(A, b, [], [], box_tops(1:3,j), [0;0;1]);
end
r = r.compile();
height_map = RigidBodyHeightMapTerrain.constructHeightMapFromRaycast(r,x0(1:nq),-1:.015:3,-1:.015:1,10);
r = r.setTerrain(height_map).compile();

v = r.constructVisualizer();
v.display_dt = 0.01;

footstep_plan = r.planFootsteps(x0(1:nq), struct('right',[1.65;-0.13;0;0;0;0],...
                                                 'left', [1.65;0.13;0;0;0;0]),...
                                safe_regions,...
                                struct('step_params', struct('max_forward_step', 0.4,...
                                                             'nom_forward_step', 0.05,...
                                                             'max_num_steps', 10)));
lcmgl = LCMGLClient('footsteps');
footstep_plan.draw_lcmgl(lcmgl);
lcmgl.switchBuffers();

% Add terrain profiles
for j = 3:length(footstep_plan.footsteps)
  [~, contact_width] = contactVolume(r, ...
                                        footstep_plan.footsteps(j-2), ...
                                        footstep_plan.footsteps(j));
  footstep_plan.footsteps(j).terrain_pts = sampleSwingTerrain(r, footstep_plan.footsteps(j-2), footstep_plan.footsteps(j), contact_width/2, struct());
end

walking_plan = r.planWalkingZMP(x0(1:nq), footstep_plan);

[ytraj, com, rms_com] = atlasUtil.simulateWalking(r, walking_plan);

v.playback(ytraj, struct('slider', true));

if ~rangecheck(rms_com, 0, 0.005);
  error('Drake:runAtlasWalkingStairs:BadCoMTracking', 'Center-of-mass during execution differs substantially from the plan.');
end

end

function [A, b] = convert_to_cspace(A, b)
  A = [A, zeros(size(A, 1), 1);
       zeros(2, size(A, 2) + 1)];
  A(end-1,3) = 1;
  A(end,3) = -1;
  b = [b; 0; 0];
end