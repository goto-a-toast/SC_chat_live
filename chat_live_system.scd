// =============================================
// Chat-Controlled Live Performance System
// Phase 1: Keyword-based Controller
// =============================================
// 使い方:
// 1. このファイル全体を選択して Cmd+Enter (Mac) / Ctrl+Enter
// 2. GUIが開く
// 3. テキストボックスにコマンドを入力してEnter
// 4. 音が変わる！
// =============================================

(
s.waitForBoot({

    // =============================================
    // 1. シンセ定義
    // =============================================

    // --- ベースシンセ（常に鳴り続けるドローン的な音） ---
    SynthDef(\chatBass, { arg freq=55, amp=0.3, gate=1, cutoff=800, res=0.3, lfoRate=0.5, lfoDepth=200;
        var sig, env, lfo;
        lfo = SinOsc.kr(lfoRate) * lfoDepth;
        sig = Saw.ar(freq, 0.5) + Pulse.ar(freq * 1.01, 0.4, 0.3);
        sig = MoogFF.ar(sig, (cutoff + lfo).clip(80, 12000), res);
        env = EnvGen.kr(Env.asr(0.5, 1, 2), gate, doneAction: 2);
        sig = sig * env * amp;
        Out.ar(0, sig ! 2);
    }).add;

    // --- パッドシンセ ---
    SynthDef(\chatPad, { arg freq=220, amp=0.2, gate=1, cutoff=2000, attack=2, release=3;
        var sig, env;
        sig = Mix.fill(5, { arg i;
            SinOsc.ar(freq * (1 + (i * 0.003)), Rand(0, 2pi)) * 0.2
        });
        sig = sig + (WhiteNoise.ar(0.01));
        sig = LPF.ar(sig, cutoff);
        env = EnvGen.kr(Env.asr(attack, 1, release), gate, doneAction: 2);
        sig = sig * env * amp;
        Out.ar(0, sig ! 2);
    }).add;

    // --- リードシンセ ---
    SynthDef(\chatLead, { arg freq=440, amp=0.15, gate=1, cutoff=3000, pw=0.5;
        var sig, env;
        sig = Pulse.ar(freq, pw) + Saw.ar(freq * 0.999);
        sig = RLPF.ar(sig, cutoff, 0.3);
        env = EnvGen.kr(Env.asr(0.01, 1, 0.3), gate, doneAction: 2);
        sig = sig * env * amp;
        Out.ar(0, sig ! 2);
    }).add;

    // --- キック ---
    SynthDef(\chatKick, { arg amp=0.5;
        var sig, env;
        env = EnvGen.kr(Env.perc(0.01, 0.4), doneAction: 2);
        sig = SinOsc.ar(60 * EnvGen.kr(Env([4, 1], [0.04], [-6]))) * env * amp;
        sig = sig + (WhiteNoise.ar(0.03) * EnvGen.kr(Env.perc(0.001, 0.05)));
        Out.ar(0, sig ! 2);
    }).add;

    // --- ハイハット ---
    SynthDef(\chatHat, { arg amp=0.1, decay=0.08;
        var sig, env;
        env = EnvGen.kr(Env.perc(0.002, decay), doneAction: 2);
        sig = HPF.ar(WhiteNoise.ar, 6000) * env * amp;
        Out.ar(0, sig ! 2);
    }).add;

    // --- スネア ---
    SynthDef(\chatSnare, { arg amp=0.3;
        var sig, env;
        env = EnvGen.kr(Env.perc(0.005, 0.2), doneAction: 2);
        sig = (SinOsc.ar(180) * EnvGen.kr(Env.perc(0.001, 0.1))) +
              (HPF.ar(WhiteNoise.ar, 2000) * 0.5);
        sig = sig * env * amp;
        Out.ar(0, sig ! 2);
    }).add;

    // --- FXバス ---
    SynthDef(\chatReverb, { arg mix=0.3, room=0.7;
        var sig;
        sig = In.ar(0, 2);
        sig = FreeVerb2.ar(sig[0], sig[1], mix, room, 0.5);
        ReplaceOut.ar(0, sig);
    }).add;

    SynthDef(\chatDelay, { arg delaytime=0.375, feedback=0.4, mix=0.3;
        var sig, delayed;
        sig = In.ar(0, 2);
        delayed = CombL.ar(sig, 2.0, delaytime, feedback * 4);
        ReplaceOut.ar(0, sig + (delayed * mix));
    }).add;

    s.sync;

    // =============================================
    // 2. 演奏エンジン
    // =============================================

    // --- グローバル状態 ---
    ~state = (
        bpm: 110,
        rootNote: 36,          // C2
        scale: Scale.minor,
        mood: \neutral,
        density: 0.5,
        chaos: 0.0,
        masterVol: 0.7,

        // 各パートのON/OFF
        bassOn: true,
        padOn: false,
        leadOn: false,
        drumOn: false,

        // シンセ参照
        bassSynth: nil,
        padSynth: nil,
        leadSynth: nil,

        // パターン参照
        drumPattern: nil,
        leadPattern: nil,

        // エフェクト
        reverbSynth: nil,
        delaySynth: nil,
        reverbMix: 0.3,
        delayMix: 0.0,
    );

    // --- スケール定義 ---
    ~moodScales = (
        bright:   Scale.major,
        neutral:  Scale.minor,
        dark:     Scale.phrygian,
        chaos:    Scale.chromatic,
        japanese: Scale.ritusen,
        blues:    Scale.blues,
        arabic:   Scale.hijaz,
    );

    // --- ベース開始/停止 ---
    ~startBass = {
        if(~state[\bassSynth].notNil, { ~state[\bassSynth].free });
        ~state[\bassSynth] = Synth(\chatBass, [
            \freq, ~state[\rootNote].midicps,
            \cutoff, 800,
            \amp, 0.3 * ~state[\masterVol]
        ]);
        ~state[\bassOn] = true;
        ">> Bass ON".postln;
    };

    ~stopBass = {
        if(~state[\bassSynth].notNil, {
            ~state[\bassSynth].set(\gate, 0);
            ~state[\bassSynth] = nil;
        });
        ~state[\bassOn] = false;
        ">> Bass OFF".postln;
    };

    // --- パッド開始/停止 ---
    ~startPad = {
        if(~state[\padSynth].notNil, { ~state[\padSynth].free });
        ~state[\padSynth] = Synth(\chatPad, [
            \freq, (~state[\rootNote] + 12).midicps,
            \cutoff, 2000,
            \amp, 0.2 * ~state[\masterVol]
        ]);
        ~state[\padOn] = true;
        ">> Pad ON".postln;
    };

    ~stopPad = {
        if(~state[\padSynth].notNil, {
            ~state[\padSynth].set(\gate, 0);
            ~state[\padSynth] = nil;
        });
        ~state[\padOn] = false;
        ">> Pad OFF".postln;
    };

    // --- ドラム開始/停止 ---
    ~startDrums = {
        if(~state[\drumPattern].notNil, { ~state[\drumPattern].stop });
        ~state[\drumPattern] = Routine({
            var stepDur;
            inf.do({ arg i;
                stepDur = 60 / ~state[\bpm] / 2; // 8th notes

                // キック: 4つ打ち + ランダム
                if((i % 4 == 0) or: { ~state[\chaos].coin }, {
                    Synth(\chatKick, [\amp, 0.5 * ~state[\masterVol]]);
                });

                // スネア: 2,4拍
                if(i % 4 == 2, {
                    Synth(\chatSnare, [\amp, 0.3 * ~state[\masterVol]]);
                });

                // ハイハット: density で密度変化
                if(~state[\density].coin, {
                    Synth(\chatHat, [
                        \amp, rrand(0.05, 0.15) * ~state[\masterVol],
                        \decay, rrand(0.03, 0.12)
                    ]);
                });

                stepDur.wait;
            });
        }).play;
        ~state[\drumOn] = true;
        ">> Drums ON".postln;
    };

    ~stopDrums = {
        if(~state[\drumPattern].notNil, {
            ~state[\drumPattern].stop;
            ~state[\drumPattern] = nil;
        });
        ~state[\drumOn] = false;
        ">> Drums OFF".postln;
    };

    // --- リード開始/停止 ---
    ~startLead = {
        if(~state[\leadPattern].notNil, { ~state[\leadPattern].stop });
        ~state[\leadPattern] = Routine({
            var stepDur, note, degrees;
            inf.do({
                stepDur = 60 / ~state[\bpm];
                degrees = ~state[\scale].degrees;

                // ランダムにスケールの音を選ぶ
                note = ~state[\rootNote] + 24 + degrees.choose;
                if(~state[\chaos] > 0.5, {
                    note = note + rrand(-2, 2); // カオス時は半音ずれる
                });

                if(~state[\density].coin, {
                    Synth(\chatLead, [
                        \freq, note.midicps,
                        \amp, 0.15 * ~state[\masterVol],
                        \cutoff, rrand(1000, 4000),
                        \gate, 1
                    ]);
                });

                (stepDur * [0.25, 0.5, 0.5, 1].choose).wait;
            });
        }).play;
        ~state[\leadOn] = true;
        ">> Lead ON".postln;
    };

    ~stopLead = {
        if(~state[\leadPattern].notNil, {
            ~state[\leadPattern].stop;
            ~state[\leadPattern] = nil;
        });
        ~state[\leadOn] = false;
        ">> Lead OFF".postln;
    };

    // --- エフェクト ---
    ~startFX = {
        ~state[\reverbSynth] = Synth.tail(s, \chatReverb, [\mix, ~state[\reverbMix]]);
        ~state[\delaySynth] = Synth.tail(s, \chatDelay, [\mix, ~state[\delayMix]]);
        ">> FX chain ready".postln;
    };

    // =============================================
    // 3. コマンドパーサー（Phase 1 のキモ！）
    // =============================================

    ~parseCommand = { arg input;
        var cmd = input.toLower.stripWhiteSpace;
        var response = "";

        // --- パート ON/OFF ---
        case
        { cmd.contains("bass on") or: { cmd.contains("ベース追加") or: { cmd.contains("bass add") } } } {
            ~startBass.value;
            response = "Bass added to the mix";
        }
        { cmd.contains("bass off") or: { cmd.contains("ベース消") or: { cmd.contains("bass remove") } } } {
            ~stopBass.value;
            response = "Bass removed";
        }
        { cmd.contains("pad on") or: { cmd.contains("パッド追加") or: { cmd.contains("pad add") } } } {
            ~startPad.value;
            response = "Pad layer added";
        }
        { cmd.contains("pad off") or: { cmd.contains("パッド消") or: { cmd.contains("pad remove") } } } {
            ~stopPad.value;
            response = "Pad removed";
        }
        { cmd.contains("drum") and: { cmd.contains("on") or: { cmd.contains("追加") or: { cmd.contains("add") } } } } {
            ~startDrums.value;
            response = "Drums are in!";
        }
        { cmd.contains("drum") and: { cmd.contains("off") or: { cmd.contains("消") or: { cmd.contains("stop") } } } } {
            ~stopDrums.value;
            response = "Drums stopped";
        }
        { cmd.contains("lead") and: { cmd.contains("on") or: { cmd.contains("追加") or: { cmd.contains("add") } } } } {
            ~startLead.value;
            response = "Lead melody started";
        }
        { cmd.contains("lead") and: { cmd.contains("off") or: { cmd.contains("消") or: { cmd.contains("stop") } } } } {
            ~stopLead.value;
            response = "Lead stopped";
        }

        // --- ムード / スケール ---
        { cmd.contains("dark") or: { cmd.contains("ダーク") } } {
            ~state[\mood] = \dark;
            ~state[\scale] = ~moodScales[\dark];
            if(~state[\bassSynth].notNil, {
                ~state[\bassSynth].set(\cutoff, 400, \res, 0.5);
            });
            if(~state[\padSynth].notNil, {
                ~state[\padSynth].set(\cutoff, 800);
            });
            ~state[\reverbMix] = 0.6;
            if(~state[\reverbSynth].notNil, { ~state[\reverbSynth].set(\mix, 0.6, \room, 0.9) });
            response = "Going dark... Phrygian scale, deep filter";
        }
        { cmd.contains("bright") or: { cmd.contains("明るく") or: { cmd.contains("happy") } } } {
            ~state[\mood] = \bright;
            ~state[\scale] = ~moodScales[\bright];
            if(~state[\bassSynth].notNil, {
                ~state[\bassSynth].set(\cutoff, 2000, \res, 0.1);
            });
            if(~state[\padSynth].notNil, {
                ~state[\padSynth].set(\cutoff, 4000);
            });
            ~state[\reverbMix] = 0.2;
            if(~state[\reverbSynth].notNil, { ~state[\reverbSynth].set(\mix, 0.2, \room, 0.4) });
            response = "Bright mode! Major scale, open filter";
        }
        { cmd.contains("blues") or: { cmd.contains("ブルース") } } {
            ~state[\mood] = \blues;
            ~state[\scale] = ~moodScales[\blues];
            response = "Blues scale activated";
        }
        { cmd.contains("japanese") or: { cmd.contains("和風") or: { cmd.contains("日本") } } } {
            ~state[\mood] = \japanese;
            ~state[\scale] = ~moodScales[\japanese];
            response = "Japanese scale (Ritusen)";
        }
        { cmd.contains("arabic") or: { cmd.contains("アラビア") or: { cmd.contains("中東") } } } {
            ~state[\mood] = \arabic;
            ~state[\scale] = ~moodScales[\arabic];
            response = "Arabic scale (Hijaz)";
        }

        // --- テンポ ---
        { cmd.contains("bpm") or: { cmd.contains("tempo") } } {
            var num = cmd.findRegexp("[0-9]+");
            if(num.size > 0, {
                var newBpm = num[0][1].asInteger;
                if((newBpm >= 40) and: { newBpm <= 300 }, {
                    ~state[\bpm] = newBpm;
                    response = "Tempo: " ++ newBpm.asString ++ " BPM";
                }, {
                    response = "BPM out of range (40-300)";
                });
            }, {
                response = "Current BPM: " ++ ~state[\bpm].asString;
            });
        }
        { cmd.contains("faster") or: { cmd.contains("速く") or: { cmd.contains("fast") } } } {
            ~state[\bpm] = (~state[\bpm] + 15).min(300);
            response = "Faster! BPM: " ++ ~state[\bpm].asString;
        }
        { cmd.contains("slower") or: { cmd.contains("遅く") or: { cmd.contains("slow") } } } {
            ~state[\bpm] = (~state[\bpm] - 15).max(40);
            response = "Slower... BPM: " ++ ~state[\bpm].asString;
        }

        // --- カオス / 密度 ---
        { cmd.contains("chaos") or: { cmd.contains("カオス") or: { cmd.contains("crazy") } } } {
            ~state[\chaos] = (~state[\chaos] + 0.3).min(1.0);
            ~state[\density] = (~state[\density] + 0.2).min(1.0);
            response = "More chaos! Level: " ++ (~state[\chaos] * 100).round.asString ++ "%";
        }
        { cmd.contains("calm") or: { cmd.contains("静か") or: { cmd.contains("chill") } } } {
            ~state[\chaos] = (~state[\chaos] - 0.3).max(0.0);
            ~state[\density] = (~state[\density] - 0.15).max(0.1);
            response = "Calming down... Chaos: " ++ (~state[\chaos] * 100).round.asString ++ "%";
        }
        { cmd.contains("sparse") or: { cmd.contains("スカスカ") } } {
            ~state[\density] = 0.2;
            response = "Sparse mode - density 20%";
        }
        { cmd.contains("dense") or: { cmd.contains("詰めて") or: { cmd.contains("busy") } } } {
            ~state[\density] = 0.9;
            response = "Dense mode - density 90%";
        }

        // --- エフェクト ---
        { cmd.contains("reverb") or: { cmd.contains("リバーブ") or: { cmd.contains("空間") } } } {
            ~state[\reverbMix] = (~state[\reverbMix] + 0.2).min(1.0);
            if(~state[\reverbSynth].notNil, {
                ~state[\reverbSynth].set(\mix, ~state[\reverbMix]);
            });
            response = "Reverb up: " ++ (~state[\reverbMix] * 100).round.asString ++ "%";
        }
        { cmd.contains("delay") or: { cmd.contains("ディレイ") or: { cmd.contains("エコー") } } } {
            ~state[\delayMix] = (~state[\delayMix] + 0.2).min(0.8);
            if(~state[\delaySynth].notNil, {
                ~state[\delaySynth].set(\mix, ~state[\delayMix]);
            });
            response = "Delay up: " ++ (~state[\delayMix] * 100).round.asString ++ "%";
        }
        { cmd.contains("dry") or: { cmd.contains("ドライ") } } {
            ~state[\reverbMix] = 0.05;
            ~state[\delayMix] = 0.0;
            if(~state[\reverbSynth].notNil, { ~state[\reverbSynth].set(\mix, 0.05) });
            if(~state[\delaySynth].notNil, { ~state[\delaySynth].set(\mix, 0.0) });
            response = "Dry signal - FX removed";
        }

        // --- フェードアウト ---
        { cmd.contains("fadeout") or: { cmd.contains("フェードアウト") or: { cmd.contains("fade out") } } } {
            response = "Fading out...";
            Routine({
                20.do({ arg i;
                    ~state[\masterVol] = (1.0 - (i / 20)) * 0.7;
                    if(~state[\bassSynth].notNil, {
                        ~state[\bassSynth].set(\amp, 0.3 * ~state[\masterVol]);
                    });
                    if(~state[\padSynth].notNil, {
                        ~state[\padSynth].set(\amp, 0.2 * ~state[\masterVol]);
                    });
                    0.15.wait;
                });
                ~stopBass.value;
                ~stopPad.value;
                ~stopDrums.value;
                ~stopLead.value;
                ~state[\masterVol] = 0.7;
                { ~statusText.string_("Faded out. Ready for new commands.") }.defer;
            }).play;
        }

        // --- リセット ---
        { cmd.contains("reset") or: { cmd.contains("リセット") } } {
            ~stopBass.value;
            ~stopPad.value;
            ~stopDrums.value;
            ~stopLead.value;
            ~state[\bpm] = 110;
            ~state[\mood] = \neutral;
            ~state[\scale] = Scale.minor;
            ~state[\chaos] = 0.0;
            ~state[\density] = 0.5;
            ~state[\masterVol] = 0.7;
            ~state[\reverbMix] = 0.3;
            ~state[\delayMix] = 0.0;
            if(~state[\reverbSynth].notNil, { ~state[\reverbSynth].set(\mix, 0.3, \room, 0.7) });
            if(~state[\delaySynth].notNil, { ~state[\delaySynth].set(\mix, 0.0) });
            response = "Reset! All cleared.";
        }

        // --- ヘルプ ---
        { cmd.contains("help") or: { cmd.contains("ヘルプ") } } {
            response = "Commands: bass/pad/lead/drums on|off, dark/bright/blues/japanese/arabic, bpm [num], faster/slower, chaos/calm, reverb/delay/dry, fadeout, reset";
        }

        // --- 未知のコマンド ---
        { true } {
            if(response.size == 0, {
                response = "? Unknown command. Type 'help' for commands.";
            });
        };

        response;
    };

    // =============================================
    // 4. GUI
    // =============================================
    {
        var win, inputField, logView, logText;
        var statusColor;

        // FXチェーン開始
        ~startFX.value;

        // ベースを開始（初期状態）
        ~startBass.value;

        win = Window("Chat Live Controller", Rect(200, 200, 500, 600))
            .background_(Color.gray(0.12));

        // --- タイトル ---
        StaticText(win, Rect(20, 10, 460, 35))
            .string_("Chat Live Performance")
            .align_(\center)
            .font_(Font("Helvetica", 20, true))
            .stringColor_(Color.new255(100, 220, 255));

        StaticText(win, Rect(20, 42, 460, 18))
            .string_("Type commands to control the music")
            .align_(\center)
            .font_(Font("Helvetica", 11))
            .stringColor_(Color.gray(0.5));

        // --- ステータス表示 ---
        ~statusText = StaticText(win, Rect(20, 70, 460, 22))
            .string_("Ready. Bass is playing.")
            .align_(\center)
            .font_(Font("Helvetica", 11, true))
            .stringColor_(Color.green(0.8));

        // --- パート状態インジケータ ---
        StaticText(win, Rect(20, 100, 460, 18))
            .string_("Active Parts:")
            .font_(Font("Helvetica", 10, true))
            .stringColor_(Color.gray(0.6));

        ~partLabels = [\BASS, \PAD, \LEAD, \DRUMS].collect({ arg name, i;
            var label = StaticText(win, Rect(20 + (i * 115), 120, 105, 28))
                .string_(name.asString)
                .align_(\center)
                .font_(Font("Helvetica", 12, true))
                .stringColor_(Color.gray(0.4))
                .background_(Color.gray(0.2));
            label;
        });

        // --- パラメータ表示 ---
        ~paramText = StaticText(win, Rect(20, 160, 460, 60))
            .string_("BPM: 110 | Scale: minor | Chaos: 0% | Density: 50%\nReverb: 30% | Delay: 0% | Mood: neutral")
            .font_(Font("Courier", 11))
            .stringColor_(Color.new255(180, 180, 220));

        // --- ログ（コマンド履歴） ---
        StaticText(win, Rect(20, 225, 460, 18))
            .string_("Command Log:")
            .font_(Font("Helvetica", 10, true))
            .stringColor_(Color.gray(0.6));

        logView = ScrollView(win, Rect(20, 245, 460, 260))
            .background_(Color.gray(0.08))
            .hasBorder_(true);

        logText = StaticText(logView, Rect(5, 5, 440, 2000))
            .string_("")
            .font_(Font("Courier", 10))
            .stringColor_(Color.green(0.7));

        ~logMessages = List[];

        ~addLog = { arg cmd, response;
            var timestamp = Date.getDate.format("%H:%M:%S");
            var displayLines;
            ~logMessages.add("> " ++ cmd);
            ~logMessages.add("  " ++ response);
            ~logMessages.add("");

            // 最新の30行だけ表示
            displayLines = if(~logMessages.size > 30, {
                ~logMessages.copyRange(~logMessages.size - 30, ~logMessages.size - 1);
            }, {
                ~logMessages;
            });

            { logText.string_(displayLines.join("\n")) }.defer;
        };

        // --- 状態更新 ---
        ~updateDisplay = {
            var bassColor = if(~state[\bassOn], { Color.cyan }, { Color.gray(0.2) });
            var padColor = if(~state[\padOn], { Color.yellow(0.8) }, { Color.gray(0.2) });
            var leadColor = if(~state[\leadOn], { Color.magenta }, { Color.gray(0.2) });
            var drumColor = if(~state[\drumOn], { Color.green(0.8) }, { Color.gray(0.2) });

            {
                ~partLabels[0].background_(bassColor);
                ~partLabels[1].background_(padColor);
                ~partLabels[2].background_(leadColor);
                ~partLabels[3].background_(drumColor);

                ~partLabels[0].stringColor_(if(~state[\bassOn], { Color.black }, { Color.gray(0.4) }));
                ~partLabels[1].stringColor_(if(~state[\padOn], { Color.black }, { Color.gray(0.4) }));
                ~partLabels[2].stringColor_(if(~state[\leadOn], { Color.black }, { Color.gray(0.4) }));
                ~partLabels[3].stringColor_(if(~state[\drumOn], { Color.black }, { Color.gray(0.4) }));

                ~paramText.string_(
                    "BPM: " ++ ~state[\bpm].asString
                    ++ " | Scale: " ++ ~state[\scale].name.asString
                    ++ " | Chaos: " ++ (~state[\chaos] * 100).round.asString ++ "%"
                    ++ " | Density: " ++ (~state[\density] * 100).round.asString ++ "%"
                    ++ "\nReverb: " ++ (~state[\reverbMix] * 100).round.asString ++ "%"
                    ++ " | Delay: " ++ (~state[\delayMix] * 100).round.asString ++ "%"
                    ++ " | Mood: " ++ ~state[\mood].asString
                );
            }.defer;
        };

        // --- テキスト入力 ---
        StaticText(win, Rect(20, 520, 460, 18))
            .string_("Enter command:")
            .font_(Font("Helvetica", 10, true))
            .stringColor_(Color.gray(0.6));

        inputField = TextField(win, Rect(20, 540, 460, 35))
            .font_(Font("Courier", 14))
            .background_(Color.gray(0.08))
            .stringColor_(Color.white)
            .action_({ arg field;
                var cmd = field.value;
                var response;

                if(cmd.size > 0, {
                    response = ~parseCommand.value(cmd);
                    ~addLog.value(cmd, response);
                    ~statusText.string_(response);
                    ~updateDisplay.value;
                    field.string_("");
                });
            });

        win.onClose_({
            ~stopBass.value;
            ~stopPad.value;
            ~stopDrums.value;
            ~stopLead.value;
            if(~state[\reverbSynth].notNil, { ~state[\reverbSynth].free });
            if(~state[\delaySynth].notNil, { ~state[\delaySynth].free });
            "Chat Live Controller closed.".postln;
        });

        win.front;
        inputField.focus;

        ~updateDisplay.value;
        "=============================================".postln;
        "  Chat Live Performance System - Phase 1    ".postln;
        "  Type commands in the GUI text field        ".postln;
        "  Type 'help' for available commands         ".postln;
        "=============================================".postln;

    }.defer;

});
)
