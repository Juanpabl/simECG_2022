function [rr, annotations, targets_beats, simECGdata, hrArray, state_history] = simECG_global_rr_intervals(sigLength, fibFreqz, realRRon, arrhythmiaParameters, simECGdata)
% [] = simECG_global_rr_intervals() generates the RR series of the
% simulated ECG record, which may include sinus rhythm, atrial
% fibrillation, atrial tachycardia, ventricular premature beats, bigeminiy
% and/or trigeminy. The rhythm switching between different arrithmias is
% performed with a Markov chain described in "ECG Modeling for Simulation
% of Arrhythmias in Time-Varying Conditions" (2023), depending on user
% parameters. AF RR intervals are generated by an atrioventricular node
% model in which the ventricles are assumed to be activated by the arriving
% atrial impulses according to a Poisson process.
% 
% Ventricular rhythm during SR is simulated using RR interval generator
% where both the impact of parasympathetic stimulation (respiratory sinus
% arrhythmia) and baroreflex regulation (Mayer waves) is modeled by a
% bimodal power spectrum, influenced by time-varying respiration.
% 
% Real RR series are either taken from either the MIT-BIH Normal Sinus
% Rhythm database, The Long Term Atrial Fibrillation or the FINCAVAS
% Exercise Stress Test database.
% 
% This function also outputs beat and rhythm annotations in the same format
% of the MIT-BIH Arrhythmia Database.
%
% Input arguments:
% sigLength - desired ECG length of the simulated record, in seconds.
% fibFreqz - frequency of fibrillatory waves, in Hz.
% realRRon - 0 for simulated RR intervals, 1 for real RR intervals.
% arrhythmiaParameters - struct of arrhythmia simulation parameters defined
% in the main script.
% simECGdata - struct of ECG simulation parameters defined in the main
% script.
%
% Output arguments:
% rr - RR series of the simulated record.
% annotations - struct of simulated ECG record annotations in the MIT-BIH
% Arrhythmia Database style.
% targets_beats - array of beat codes.
% simECGdata - struct of ECG simulation parameters defined in the main
% script (updated).
% hrArray - for stress test ECG, this variable is an array of heart rate
% during excercise. For non stress test ECG simulations, this variable is
% just an array of average heart rate.
% state_history - array of Markov chain states.
% 
% Licensed under GNU General Public License version 3:
% https://www.gnu.org/licenses/gpl-3.0.html


% The desired ECG signal length in number of RR intervals 
% rrLength = round(sigLength/0.2);
rrLength = 5*sigLength;

% signal length in ms
sigLengthMs = sigLength * 1000;
simECGdata.Fr = [];

% fetching arrhythmia parameters
B_af = arrhythmiaParameters.B_af;
d_af = arrhythmiaParameters.d_af;
B_at = arrhythmiaParameters.B_at;
dist_at = arrhythmiaParameters.at_dist;
at_x = arrhythmiaParameters.at_x;
B_vpb = arrhythmiaParameters.B_vpb;
B_bt = arrhythmiaParameters.B_bt;
p_bt = arrhythmiaParameters.p_bt;
d_bt = arrhythmiaParameters.d_bt;
apb_p = arrhythmiaParameters.apb_p; apb_p = apb_p ./sum(apb_p);
vpb_p = arrhythmiaParameters.vpb_p; vpb_p = vpb_p ./sum(vpb_p);
if B_at>0
    dist_at = dist_at./ sum(dist_at);
end
d_at = sum(dist_at.*(at_x));
if B_vpb>0.9
    B_vpb = 0.9;
end
TB = B_at+B_af+B_bt+B_vpb;
if (TB)>1
    B_at = B_at / TB;
    B_af = B_af / TB;
    B_bt = B_bt / TB;
    B_vpb = B_vpb / TB;
end
if d_af < 1, d_af = 1; end
if d_bt < 1, d_bt = 1; end
%load('AT_RRi_Dist');
% beat codes for annotation production
beatCodes = ['N','A','V','+']; % please note: if new beat types are added, '+' should always be last
rhythmCodes = {'(N','(AFIB','(SVTA','(B','(T'};

% Choice of rhythm to generate
if simECGdata.ESTflag == 1 %Lorenzo 06/2022
    rhythmType = 1; % SR and EST
    if B_af ~= 0
        B_af = 0;
        disp('Warning: excercise stress test activated, AF burden set to zero.');
    end
else
    rhythmType = 0; % SR
end

disp('Generating RR intervals ...');

%% RR generation
rr_af = [];
switch rhythmType  % 0 - regular ECG, 1 - stress ECG
    case 0
        
        % Generate sinus node pacing activity
        srLength = rrLength;
        if realRRon == 1 % Use real RR series
            rr_sr = simECG_get_real_RR_intervals(0, srLength); % sinus rhythm rr series (real)
            hrArray = (1./rr_sr)*60 ;
        else % Use simulated RR series
            [rr_sr,hrArray,simECGdata] = simECG_generate_sinus_rhythm(srLength,simECGdata); % sinus rhythm rr series
            %sigLength = ceil(simECGdata.Duration);
%             rr_sr = rr_sr(1:srLength);
        end
        
        % Generate atrial fibrillation pacing activity
        if B_af > 0
            afLength = round(2.5*sigLength*B_af);
            if realRRon == 1 % Use real RR series
                rr_af = simECG_get_real_RR_intervals(1, afLength);  %atrial fibrillation rr series
            else
                rr_af = simECG_generate_AF_intervals(fibFreqz,afLength); %atrial fibrillation rr series
                rr_af = rr_af(1:afLength);
            end
        end
        
        % Make sure that the average RR value during SR is larger than that in AF
        if mean(rr_sr) < mean(rr_af)
            rr_sr = rr_sr + (mean(rr_af) - mean(rr_sr));
        end
        
        
    case 1 % The entire rhythm is SR but for EST signal %CPerez 06/2021
        srLength = [];
        if realRRon == 1 % Use real RR series
            [rr_sr, simECGdata.peak, fa, simECGdata.ecgnr] = simECG_get_real_RR_intervals(2,rrLength); % If opt == 1 - AF, If opt == 2 - SR for stress test
             
            L = 300;
            if  realRRon %CPerez 04/2022. To take into account the influence of the "QT memory" before starting the EST
                rep = ceil(L/rr_sr(1));
                rr_sr = [repmat(rr_sr(1),rep,1); rr_sr];
            end
             
            dHR = 60./rr_sr; %instantaneous HR
            timebeats = [0; cumsum(rr_sr(2:end))]; %In seconds
            [pos, dHRu] = resamp(dHR,timebeats.*fa,fa,4);%4Hz resample
            pos = pos./fa;
            [b,a] = butter(2,0.03); %Fc = 0.03Hz
            hrMeanu = filtfilt(b,a,dHRu);
            hrArray = interp1(pos, hrMeanu, timebeats);
            simECGdata.Duration = sum(rr_sr); %in seconds
            
            %Recalculate the exercise peak
            posPeak = sort(find(round(rr_sr,3)==min(round(rr_sr,3)))); %peak position
            if length(posPeak)>1
                posPeak = posPeak(round(length(posPeak)/2));
            end
            simECGdata.peak = sum(rr_sr(1:posPeak));
            
            
            simECGdata.Frini = [];
            simECGdata.Frpeak = [];
            simECGdata.Frend = [];
            
            sigLength = ceil(simECGdata.Duration);
            sigLengthMs = sigLength * 1000;
            
        else % Use synthetic RR series CPerez 04/2022
            [rr_sr, hrArray, simECGdata] = simECG_generate_sinus_rhythm(rrLength, simECGdata);
            sigLength = fix(simECGdata.Duration); %in sec
            sigLengthMs = sigLength * 1000; %in msec
        end
        rhythm_states = ones(1,sigLength);
        rr_af = Inf;
end

% Put HR in a vector to allow compatibility with stress test
if length(hrArray) ==1
    hrArray = ones(1,length(rr_sr)+1)*hrArray;
end

%% Markov chain transition matrix
% State names
%  state 1: SR
%  state 2: AF
%  state 3: AT
%  state 4: BT
%  state 5: VPB in SR
%  state 6: VPB in AT
%  state 7: VPB in AF
sN = {'1';'2';'3';'4';'5';'6';'7'};
% starting (previous) state of the Markov chain
ps = 1;
% Markov chain transition probability matrix
transM = zeros(7);

% distributions from mean episode durations
% atrial fibrillation
%a_af= 33.54; %b_af = 0.012358;
b_af = 1/d_af;
dist_af = (exp((-b_af)*(5:800)));
dist_af = dist_af ./ sum(dist_af);
d_afr = sum((5:800).*dist_af);
d_af2 = d_af;
while abs(d_afr-d_af)>0.01
    d_af2 = d_af2 + 1*(d_af - d_afr);
    b_af = 1/d_af2;
    dist_af = (exp((-b_af)*(5:800)));
    dist_af = dist_af ./ sum(dist_af);
    d_afr = sum((5:800).*dist_af);
end
% bigeminy, trigeminy
%a_bt = 248.4; %b_bt = 0.2029;
b_bt = 1/d_bt;
dist_bt = (exp((-b_bt)*(4:80)));
dist_bt = dist_bt ./ sum(dist_bt);
d_btr = sum((4:80).*dist_bt);
d_bt2 = d_bt;
while abs(d_btr-d_bt)>0.01
    d_bt2 = d_bt2 + 1*(d_bt - d_btr);
    b_bt = 1/d_bt2;
    dist_bt = (exp((-b_bt)*(4:80)));
    dist_bt = dist_bt ./ sum(dist_bt);
    d_btr = sum((4:80).*dist_bt);
end

T = sigLength;
% average RR interval in SR
d_RR_sr = 60/mean(hrArray);
% average RR interval in AT
d_RR_at = d_RR_sr ;
% average RR interval in AF
d_RR_af = 0.765;
% average RR interval in BT
d_RR_bt = d_RR_sr ;
% mean episode duration of a VPB event (NOTE: related to the dominant
% rhythm!)
d_vpb_sr = mean( vpb_p(1) + (vpb_p(2)*0.725) + (vpb_p(3)*0.6) );
d_vpb_at = 1;
d_vpb_af = 1;
% sinus rhythm burden
B_sr = 1 - ( B_at + B_af + B_bt + B_vpb ) ;
% VPB burden scaling factor
B = 1 / ( B_at + B_af + B_sr ) ;
if B==Inf
    B=0;
end
% splitting VPB burden
% B_vpb_at and B_vpb_af must be constrained in order to avoid too many
% transitions to AT or AF which would break the burden constraint
if (arrhythmiaParameters.vpbs_in_at == 1)
    B_vpb_at = min(B_vpb * B_at * B, ((0.5*B_at*d_vpb_at)/(d_at)));
else
    B_vpb_at = 0;
end
if (arrhythmiaParameters.vpbs_in_af == 1)
    B_vpb_af = min(B_vpb * B_af * B, ((0.5*B_af*d_vpb_af)/(d_af)));
else
    B_vpb_af = 0;
end
B_vpb_sr = B_vpb - B_vpb_at - B_vpb_af;
% contribution to n_sr from the AT branch of the Markov chain
n1 = ( ( ( d_vpb_at * B_at * T ) - ( d_at * B_vpb_at * T ) ) / ( d_vpb_at * d_at * d_RR_at ) );
% contribution from the BT branch
n2 = ( ( B_bt * T ) / ( d_bt * d_RR_bt ) );
% contribution from the AF branch
n3 = ( ( ( d_vpb_af * B_af * T ) - ( d_af * B_vpb_af * T ) ) / ( d_vpb_af * d_af * d_RR_af ) );
% contribution from the SR -> VPB branch
n4 = ( ( B_vpb_sr * T ) / ( d_vpb_sr * d_RR_sr ) );
% number of SR episodes (from manuscript Appendix A)
n_sr = max((n1 + n2 + n3 + n4),1);

% mean SR episode duration
if B_sr>0
    d_sr = max(( T * B_sr ) / ( n_sr * d_RR_sr ),1);
else
    d_sr=1;
end
b_sr = 1/d_sr;
dist_sr = (exp((-b_sr)*(1:rrLength)));
dist_sr = dist_sr ./ sum(dist_sr);
d_srr = sum((1:rrLength).*dist_sr);
d_sr2 = d_sr;
while abs(d_srr-d_sr)>0.01
    d_sr2 = d_sr2 + 1*(d_sr - d_srr);
    b_sr = 1/d_sr2;
    dist_sr = (exp((-b_sr)*(1:rrLength)));
    dist_sr = dist_sr ./ sum(dist_sr);
    d_srr = sum((1:rrLength).*dist_sr);
end

% Transition probabilities
% SR -> VPB
if (B_sr>0)&&(B_vpb_sr>0)
    p_SR_VPB = n4 / n_sr;
    p_VPB_SR = 1;
else
    p_SR_VPB = 0;
    p_VPB_SR = 0;
end
if B_sr == 1
    transM(1,1) = 1;
end
% AT branch transition to VPB
if (B_at>0)&&(B_vpb_at>0)
    if B_sr >0
        p_AT_VPB = ( B_vpb_at * d_at ) / ( B_at * d_vpb_at );
    else
        p_AT_VPB = 1;
    end
    p_VPB_AT = 1;
else
    p_AT_VPB = 0;
    p_VPB_AT = 0;
end
% AF branch transition to VPB
if (B_af>0)&&(B_vpb_af>0)
    if B_sr >0
        p_AF_VPB = ( B_vpb_af * d_af ) / ( B_af * d_vpb_af );
    else
        p_AF_VPB = 1;
    end
    p_VPB_AF = 1;
else
    p_AF_VPB = 0;
    p_VPB_AF = 0;
end
% check if sinus rhythm is present in the record
if B_sr > 0
    p_SR_AT = n1 / n_sr;
    p_AT_SR = 1 - p_AT_VPB;
    p_SR_AF = n3 / n_sr;
    p_AF_SR = 1 - p_AF_VPB;
    p_SR_BT = n2 / n_sr;
    p_BT_SR = 1;
else
    [B, index] = max([0, B_af, B_at, B_bt]);
    ps = index;
    p_SR_AT = 0;
    p_AT_SR = 0;
    p_SR_AF = 0;
    p_AF_SR = 0;
    p_SR_BT = 0;
    p_BT_SR = 0;
    if B == 1
        transM(ps,ps) = 1;
    end
end

transM(1,2) = p_SR_AF;
transM(2,1) = p_AF_SR;
transM(1,3) = p_SR_AT;
transM(3,1) = p_AT_SR;
transM(1,4) = p_SR_BT;
transM(4,1) = p_BT_SR;
transM(1,5) = p_SR_VPB;
transM(5,1) = p_VPB_SR;
transM(2,6) = p_AF_VPB;
transM(6,2) = p_VPB_AF;
transM(3,7) = p_AT_VPB;
transM(7,3) = p_VPB_AT;    

% time counter
t = 0;
% rr, target beats and state history vectors initialization
targets_beats = zeros(1,rrLength);
rr = zeros(1,rrLength);
state_history = zeros(1,rrLength);
% beat counter
k = 0;
% annotation vectors initialization
annTime = zeros(1,2*rrLength);
annType = char(zeros(1,2*rrLength));
annRhythm = cell(1,2*rrLength);
kann = 0;
% rhythm check, used to annotate rhythm changes
rc = 0;
% rhythm counters
c_SR = 1;
c_AF = 1;
% RR series generation loop
while t<=sigLengthMs
    % the "hmmgenerate" command assumes that the starting state of the HMM
    % is always the first one. However, in the simulator, we generate one
    % state at a time. This means that the initial state needs to be
    % swapped with state 1 after each state is drawn from the Markov
    % chain.
    if k>0
        states = (1:7)';
        temp = states(ps);
        states(ps) = 1;
        states(1) = temp;
        [~,ss] = hmmgenerate(1,transM(states,states),states,'Statenames',sN(states));
        s = str2double(ss);
    else
        s = ps;
    end
    switch s
        case 1
            % SR
            % sampling the sinus rhythm episode length distribution
            x = find(rand<=cumsum(dist_sr));
            % duration is the first nonzero index of rand<=cumDist
            d = x(1);
            for c = 1:d
                % states counter
                k = k + 1;
                % memorize state
                state_history(k) = s;
                % insert normal beat
                rr(k) = rr_sr(c_SR);
                % check if rhythm annotation should change
                if rc~=1
                    % rhythm annotation - N
                    kann=kann+1;
                    annTime(kann) = t + ceil((rr(k)*1000)/2);
                    annType(kann) = beatCodes(end);
                    annRhythm{kann}= rhythmCodes(1);
                    % rhythm check
                    rc = 1;
                end
                % update time counter
                t = t + ceil(rr(k)*1000);
                % increase SR counter
                c_SR = c_SR + 1;
                % beat annotation
                kann=kann+1;
                annTime(kann) = round(t);
                annType(kann) = beatCodes(1);
                annRhythm{kann} = [];
                % update targets array
                targets_beats(k) = 1;
                % check whether RR simulation should be terminated
                if t>sigLengthMs
                    break;
                end
            end
        case 2
            % AF
            % sampling the atrial fibrillation episode length distribution
            x = find(rand<=cumsum(dist_af)) + 4;
            % duration is the first nonzero index of rand<=cumDist
            d = x(1);
            for c = 1:d
                % states counter
                k = k + 1;
                % memorize state
                state_history(k) = s;
                % occasionally, AF episodes run very long
                if c_AF>length(rr_af)
                    if realRRon == 1
                        rr_af = [rr_af,simECG_get_real_RR_intervals(1, afLength)];
                    else
                        rr_af = [rr_af,simECG_generate_AF_intervals(fibFreqz,afLength)'];
                    end
                end
                % avoid too large RR intervals in simulated AF
                while (rr_af(c_AF)>1.8)&&(realRRon == 0)
                    c_AF = c_AF + 1;
                end
                % insert af beat from Corino's AV model
                rr(k) = rr_af(c_AF);
                % check if rhythm annotation should change
                if rc~=2
                    % rhythm annotation - AFIB
                    kann=kann+1;
                    annTime(kann) = t + round((rr(k)*1000)/2);
                    annType(kann) = beatCodes(end);
                    annRhythm{kann}= rhythmCodes(2);
                    % rhythm check
                    rc = 2;
                end
                % update time counter
                t = t + round(rr(k)*1000);
                % increase AF counter
                c_AF = c_AF + 1;
                % beat annotation
                kann=kann+1;
                annTime(kann) = round(t);
                annType(kann) = beatCodes(1);
                annRhythm{kann} = [];
                % update targets array
                targets_beats(k) = 2;
                % check whether RR simulation should be terminated
                if t>sigLengthMs
                    break;
                end
            end
        case 3
            % AT
            % sampling the tachycardia episode length distribution
            x = find(rand<=cumsum(dist_at));
            % duration is the first nonzero index of rand<=cumDist
            d = x(1);
            if (ps==3)
                % avoid too short RR intervals if, for some reason, two
                % AT states follow each other (eg, B_at = 1)
                c_SR = c_SR + 1;
            end
            for c = 1:d
                % states counter
                k = k + 1;
                % memorize state
                state_history(k) = s;
                if d == 1
                    % isolated APB
                    % select APB type
                    ap = cumsum(apb_p);
                    apbtype = find(rand<=ap,1);
                    switch apbtype
                        case 1 % APBs with sinus reset
                            % prematurity factor
                            beta_APB1_p = 0.55 + rand*0.4;
                            % rr interval of the apb
                            rrtemp = rr_sr(c_SR) * beta_APB1_p;
                            % No compensatory pause
                        case 2 % APBs with delayed sinus reset
                            % prematurity factor
                            beta_APB2_p = 0.55 + rand*0.4;
                            % rr interval of the apb
                            rrtemp = rr_sr(c_SR) * beta_APB2_p;
                            % delay factor
                            beta_APB2_f = 1.1 + rand*0.25;
                            % apb compensatory pause
                            rr_sr(c_SR+1) = rr_sr(c_SR+1) * beta_APB2_f;
                        case 3 % APBs with full compensatory pause
                            % prematurity factor
                            beta_APB3_p = 0.55 + rand*0.4;
                            % rr interval of the apb
                            rrtemp = rr_sr(c_SR) * beta_APB3_p;
                            % apb compensatory pause
                            rr_sr(c_SR+1) = (2*rr_sr(c_SR+1)) - rrtemp;
                        case 4 % Interpolated APBs
                            % prematurity factor
                            beta_APB4_p = 0.45 + rand*0.1;
                            % rr interval of the apb
                            rrtemp = rr_sr(c_SR) * beta_APB4_p;
                            % apb compensatory pause
                            rr_sr(c_SR+1) = rr_sr(c_SR+1) - rrtemp;
                    end
                else
                    if c == 1
                        % Tachycardia episode begins
                        bpm_at = ( rand*(2-1.1) + 1.1 ) * hrArray(c_SR);
                        % excessive rates are discarded
                        it = 1;
                        while (bpm_at > 200)||(bpm_at < 100)
                            bpm_at = ( rand*(2-1.1) + 1.1 ) * hrArray(c_SR);
                            it = it + 1;
                            if it == 10
                                bpm_at = 100*rand + 100;
                            end
                        end
                        beta_AT = hrArray(c_SR) / bpm_at;
                        % prematurity factor
                        beta_AT_p = 0.55 + rand*0.4;
                        % base RR of the AT episode
                        rr0 = rr_sr(c_SR);
                        % rr interval of the first beat of the AT episode
                        rrtemp = rr0 * beta_AT_p;
                        % delay factor
                        beta_AT_f = rand*(1.5-0.7) + 0.7;
                        % apb compensatory pause
                        rr_sr(c_SR+1) = rr_sr(c_SR+1) * beta_AT_f;
                        % tachycardia annotation
                        if rc~=3
                            % rhythm annotation - SVTA
                            kann=kann+1;
                            annTime(kann) = t + round(0.5*(rrtemp*1000));
                            annType(kann) = beatCodes(end);
                            annRhythm{kann}= rhythmCodes(3);
                            rc=3;
                        end
                    else
                        % tachycardia episode continues
                        rrtemp = 0;
                        while rrtemp<0.200
                            %old variability: uniform distribution
                            
                            % variability of AT RR intervals
                            at_var = 0.05;
                            % beat to beat variation
                            delta_d_RR = (rand*at_var*2) - at_var ;
                            
                            % new variability: distribution from fitted  data
                            %{
                            % sampling distribution
                            x = find(rand<=cumsum(AT_RRi_YData),1);
                            % variability of current RR interval
                            delta_d_RR = AT_RRi_XData(x);
                            %}
                            % current rr interval of the episode
                            f = beta_AT;
                            rrtemp = f * rr0 + delta_d_RR ;
                        end
                    end
                end
                % insert atrial beat
                rr(k) = rrtemp;
                % update time counter
                t = t + round(rr(k)*1000);
                % increase SR counter
                c_SR = c_SR + 1;
                % beat annotation
                kann=kann+1;
                annTime(kann) = round(t);
                annType(kann) = beatCodes(2);
                annRhythm{kann} = [];
                % update targets array
                targets_beats(k) = 3;
                % check whether RR simulation should be terminated
                if t>sigLengthMs
                    break;
                end
            end
        case 4
            % BT
            % sampling the bigeminy/trigeminy episode length distribution
            x = find(rand<=cumsum(dist_bt)) + 3;
            % duration is the first nonzero index of rand<=cumDist
            d = x(1);
            % prematurity factor of the episode
            beta_BT_base = 0.6 + rand*0.15;
            if (ps ~= 4)||(k==0)
                % decision between trigeminy and bigeminy
                x = rand;
                if x>p_bt(1)
                    % trigeminy
                    BT_type = 3;
                    ann = rhythmCodes(5);
                    % check minimum duration
                    if d<6
                        d=6;
                    else
                        if mod(d,3)~=0
                            d=round(d/3)*3;
                        end
                    end
                else
                    % bigeminy
                    BT_type = 2;
                    ann = rhythmCodes(4);
                    % check minimum duration
                    if d<4
                        d=4;
                    else
                        if mod(d,2)~=0
                            if rand>=05
                                d=d+1;
                            else
                                d=d-1;
                            end
                        end
                    end
                end
                bt_flag = BT_type;
            end
            for c = 1:d
                % states counter
                k = k + 1;
                % memorize state
                state_history(k) = s;
                if bt_flag>1
                    % insert normal beat
                    rr(k) = rr_sr(c_SR);
                    % check if rhythm annotation should change
                    if rc~=4
                        % rhythm annotation - B or T
                        kann=kann+1;
                        annTime(kann) = t + round((rr(k)*1000)/2);
                        annType(kann) = beatCodes(end);
                        annRhythm{kann}= ann;
                        % rhythm check
                        rc = 4;
                    end
                    % update time counter
                    t = t + round(rr(k)*1000);
                    % update SR counter
                    c_SR = c_SR + 1;
                    % beat annotation
                    kann=kann+1;
                    annTime(kann) = round(t);
                    annType(kann) = beatCodes(1);
                    annRhythm{kann} = [];
                    % update targets array
                    targets_beats(k) = 1;
                    % beat insterted
                    bt_flag = bt_flag - 1;
                else
                    % ventricular beat
                    % prematurity factor
                    beta_BT_p = beta_BT_base + ((rand-0.5)/10);
                    % rr interval of the apb
                    rr(k) = rr_sr(c_SR) * beta_BT_p;
                    % delay factor
                    %beta_BT_f = 1.1 + rand*0.2;
                    % vpb compensatory pause
                    %rr_sr(c_SR) = rr_sr(c_SR) * beta_BT_f;
                    rr_sr(c_SR) = (2*rr_sr(c_SR)) - rr(k);
                    % update time counter
                    t = t + round(rr(k)*1000);
                    % beat annotation
                    kann=kann+1;
                    annTime(kann) = round(t);
                    annType(kann) = beatCodes(3);
                    annRhythm{kann} = [];
                    % update targets array
                    targets_beats(k) = 4;
                    % the next beat should be normal
                    bt_flag = BT_type;
                end
                % check whether RR simulation should be terminated
                if t>sigLengthMs
                    break;
                end
            end
        case 5
            % Isolated VPB in SR
            % states counter
            k = k + 1;
            % memorize state
            state_history(k) = s;
            % select VPB type
            vp = cumsum(vpb_p);
            vpbtype = find(rand<=vp,1);
            switch vpbtype
                case 1 % VPBs with full compensatory pause
                    % prematurity factor
                    beta_VPB1_p = 0.55 + rand*0.35;
                    % rr interval of the vpb
                    rrtemp = rr_sr(c_SR) * beta_VPB1_p;
                    % vpb compensatory pause
                    rr_sr(c_SR) = (2*rr_sr(c_SR)) - rrtemp;
                case 2 % VPBs with non compensatory pause
                    % prematurity factor
                    beta_VPB2_p = 0.55 + rand*0.35;
                    % rr interval of the apb
                    rrtemp = rr_sr(c_SR) * beta_VPB2_p;
                case 3 % Interpolated VPBs
                    % prematurity factor
                    beta_VPB3_p = 0.45 + rand*0.1;
                    % rr interval of the apb
                    rrtemp = rr_sr(c_SR) * beta_VPB3_p;
                    % apb compensatory pause
                    rr_sr(c_SR) = rr_sr(c_SR) - rrtemp;
            end
            % insert ventricular beat
            rr(k) = rrtemp;
            % update time counter
            t = t + round(rr(k)*1000);
            % beat annotation
            kann=kann+1;
            annTime(kann) = round(t);
            annType(kann) = beatCodes(3);
            annRhythm{kann} = [];
            % update targets array
            targets_beats(k) = 4;
        case 6
            % Isolated VPB during AF - same RR of Corino's model
            % states counter
            k = k + 1;
            % memorize state
            state_history(k) = s;
            % avoid too large RR intervals in AF
            while rr_af(c_AF)>1.8
                c_AF = c_AF + 1;
            end
            rrtemp = rr_af(c_AF);
            % insert ventricular beat
            rr(k) = rrtemp;
            % update time counter
            t = t + round(rr(k)*1000);
            % beat annotation
            kann=kann+1;
            annTime(kann) = round(t);
            annType(kann) = beatCodes(3);
            annRhythm{kann} = [];
            % update targets array
            targets_beats(k) = 4;
        case 7
            % isolated VPB during AT
            % states counter
            k = k + 1;
            % memorize state
            state_history(k) = s;
            % rr interval of the vpb
            rrtemp = rr_sr(c_SR);
            % insert ventricular beat
            rr(k) = rrtemp;
            % update time counter
            t = t + round(rr(k)*1000);
            % increase SR counter
            c_SR = c_SR + 1;
            % beat annotation
            kann=kann+1;
            annTime(kann) = round(t);
            annType(kann) = beatCodes(3);
            annRhythm{kann} = [];
            % update targets array
            targets_beats(k) = 4;
    end
    ps = s;
end
targets_beats = targets_beats(1:k);
rr = rr(1:k);
state_history = state_history(1:k);
annTime = annTime(1:kann);
annType = annType(1:kann);
annRhythm = annRhythm(1:kann);
annotations.annTime = annTime;
annotations.annType = annType;
annotations.annRhythm = annRhythm;

%% Number and boundaries of PAF episodes
% k = 1;
% pafEpisodeLength = [];
% for p = 1:length(state_history)-1
%     if state_history(p) == 2
%         if state_history(p+1) == 2
%             k = k + 1;
%             if p == (length(state_history)-1)
%                 pafEpisodeLength = [pafEpisodeLength k];
%             end
%         else
%             pafEpisodeLength = [pafEpisodeLength k];
%             k = 1;
%         end
%     end
% end
% pafBoundaries=0;
% % Find boundaries of each PAF episode
% if prod(state_history == 1)==1 % The entire signal is SR
%     pafBoundaries(1,1) = 0;
%     pafBoundaries(1,2) = 0;
% elseif prod(state_history == 2)==1 % The entire signal is AF
%     pafBoundaries(1,1) = 1;
%     pafBoundaries(1,2) = length(rr);
% else % The signal with PAF
%     diffTar = diff(state_history);
%     j = 1;
%     k = 1;
%     flag = 1;
%     for i = 1:length(diffTar)
%         if diffTar(i) == 1
%             pafBoundaries(j,1) = i + 1;
%             j = j + 1;
%             flag = 1;
%         end
%         if diffTar(i) == -1
%             pafBoundaries(k,2) = i;
%             k = k + 1;
%             flag = 2;
%         end
%         
%         if i == length(diffTar)
%             if flag == 1
%                 pafBoundaries(k,2) = i+1;
%             end
%         end
%     end
% end

end