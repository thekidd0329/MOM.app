import 'discovery_models.dart';

DiscoveryChoice _c(
  String nodeId,
  String suffix,
  String label,
  String detail,
  Map<String, double> signals,
  List<String> opens, {
  List<String> suppresses = const [],
  double certainty = .9,
}) {
  return DiscoveryChoice(
    id: '${nodeId}_$suffix',
    label: label,
    detail: detail,
    signals: signals,
    opens: opens,
    suppresses: suppresses,
    certainty: certainty,
  );
}

List<DiscoveryChoice> choicesFor(String domain, String nodeId) {
  // The first four questions are routing gates and get bespoke paths.
  if (nodeId == 'orientation_when_life_slips') {
    return [
      _c(nodeId, 'stuff', 'Small things start disappearing', 'Keys, dates, plans, objects, little promises.', const {'memory_support_need': .8, 'external_prompting': .5}, const ['memory', 'time', 'structure'], certainty: .95),
      _c(nodeId, 'overload', 'My brain gets overloaded', 'Everything feels too loud, fast, emotional, or tangled.', const {'emotional_sensitivity': .8, 'sensory_sensitivity': .3}, const ['stress', 'emotion', 'sensory'], certainty: .95),
      _c(nodeId, 'start', 'I stop getting started', 'I know what needs doing but cannot get traction.', const {'task_initiation': -.8}, const ['task_start', 'motivation', 'competence'], certainty: .95),
      _c(nodeId, 'varies', 'It changes every time', 'There is not one failure pattern.', const {'openness': .2}, const ['decision', 'attention', 'stress'], certainty: .45),
    ];
  }
  if (nodeId == 'orientation_mom_role') {
    return [
      _c(nodeId, 'memory', 'Remember the life stuff', 'Catch what I forget and bring it back when it matters.', const {'memory_support_need': .9}, const ['memory', 'time'], certainty: .95),
      _c(nodeId, 'momentum', 'Keep me moving', 'Help me start, finish, and recover when I fall off.', const {'task_initiation': -.5, 'external_prompting': .7}, const ['task_start', 'motivation', 'structure'], certainty: .95),
      _c(nodeId, 'understand', 'Know me deeply', 'Learn my patterns, people, moods, and what matters.', const {'relatedness_need': .6, 'reflection_preference': .6}, const ['emotion', 'relatedness', 'values_goals'], certainty: .95),
      _c(nodeId, 'all', 'Honestly, all of it', 'I want MOM integrated across the whole mess.', const {'external_prompting': .6, 'openness': .5}, const ['memory', 'task_start', 'emotion', 'values_goals'], certainty: .7),
    ];
  }
  if (nodeId == 'orientation_reminder_feel') {
    return [
      _c(nodeId, 'gentle', 'A quiet tap on the shoulder', 'Noticeable without making me feel managed.', const {'directness_preference': -.2, 'autonomy_need': .6}, const ['communication', 'autonomy'], certainty: .95),
      _c(nodeId, 'direct', 'Straight to the point', 'Tell me what I am about to forget.', const {'directness_preference': .8, 'external_prompting': .5}, const ['communication', 'time'], certainty: .95),
      _c(nodeId, 'persistent', 'Do not let me wiggle out of it', 'If it matters, keep bringing it back until I act.', const {'external_prompting': .95, 'structure_need': .5}, const ['motivation', 'task_start'], certainty: .95),
      _c(nodeId, 'adaptive', 'Read the room', 'Some moments need gentle, some need blunt.', const {'emotional_sensitivity': .3, 'directness_preference': .1}, const ['stress', 'emotion', 'communication'], certainty: .55),
    ];
  }
  if (nodeId == 'orientation_control_level') {
    return [
      _c(nodeId, 'ask', 'Ask before taking over', 'Help hard, but keep me in the driver\'s seat.', const {'autonomy_need': .9}, const ['autonomy', 'decision'], certainty: .95),
      _c(nodeId, 'recommend', 'Give me a strong recommendation', 'I still choose, but do not make me drag it out of you.', const {'autonomy_need': .5, 'directness_preference': .7}, const ['decision', 'communication'], certainty: .95),
      _c(nodeId, 'lead', 'Take the lead on obvious stuff', 'If I already told you the rule, use it.', const {'autonomy_need': .2, 'external_prompting': .8}, const ['structure', 'task_start'], certainty: .9),
      _c(nodeId, 'context', 'Depends how serious it is', 'Routine stuff and high-stakes stuff should not work the same.', const {'autonomy_need': .6, 'risk_tolerance': .1}, const ['decision', 'stress'], certainty: .6),
    ];
  }

  switch (domain) {
    case 'orientation':
      return [
        _c(nodeId, 'practical', 'The practical stuff', 'Help with the things that make daily life wobble.', const {'external_prompting': .6}, const ['memory', 'time', 'task_start'], certainty: .9),
        _c(nodeId, 'inner', 'How my brain works', 'Patterns, emotions, motivation, and what makes me me.', const {'reflection_preference': .7}, const ['emotion', 'motivation', 'values_goals'], certainty: .9),
        _c(nodeId, 'people', 'My people', 'Relationships and social context are a huge part of my life.', const {'relatedness_need': .8}, const ['relatedness', 'attachment_support'], certainty: .9),
        _c(nodeId, 'mixed', 'A little of everything', 'I do not fit neatly into one lane.', const {'openness': .3}, const ['decision', 'attention', 'communication'], certainty: .5),
      ];
    case 'structure':
      return [
        _c(nodeId, 'rails', 'More structure helps me', 'Clear rails make my brain quieter.', const {'structure_need': .9, 'conscientiousness': .2}, const ['task_start', 'time'], certainty: .95),
        _c(nodeId, 'loose', 'A loose framework', 'I want anchors, not a cage.', const {'structure_need': .4, 'autonomy_need': .5}, const ['autonomy', 'time'], certainty: .85),
        _c(nodeId, 'flex', 'Keep it flexible', 'Too much structure makes me resist it.', const {'structure_need': -.7, 'autonomy_need': .8}, const ['autonomy', 'openness'], certainty: .9),
        _c(nodeId, 'depends', 'Depends on the day', 'My need for structure changes with context.', const {'structure_need': 0, 'emotional_sensitivity': .2}, const ['stress', 'decision'], certainty: .45),
      ];
    case 'task_start':
      return [
        _c(nodeId, 'jump', 'I just jump in', 'Starting is usually easier than thinking about it.', const {'task_initiation': .9, 'conscientiousness': .3}, const ['attention', 'time'], certainty: .95),
        _c(nodeId, 'first', 'Show me the first step', 'Once the doorway is obvious, I can move.', const {'task_initiation': -.3, 'structure_need': .7, 'competence_need': .5}, const ['structure', 'competence'], certainty: .9),
        _c(nodeId, 'pressure', 'I need pressure or company', 'Urgency or another person gets the engine turning.', const {'task_initiation': -.5, 'external_prompting': .8, 'relatedness_need': .4}, const ['motivation', 'relatedness'], certainty: .9),
        _c(nodeId, 'depends', 'Depends what it is', 'Interest and context completely change the answer.', const {'novelty_preference': .3}, const ['motivation', 'attention', 'values_goals'], certainty: .45),
      ];
    case 'memory':
      return [
        _c(nodeId, 'reliable', 'Pretty reliable', 'I usually remember without building a system around it.', const {'memory_support_need': -.8}, const ['attention'], certainty: .95),
        _c(nodeId, 'capture', 'Good if I capture it', 'My memory works when I externalize things.', const {'memory_support_need': .5, 'conscientiousness': .3}, const ['structure', 'time'], certainty: .9),
        _c(nodeId, 'mom', 'Please remember for me', 'Future me cannot be trusted with loose information.', const {'memory_support_need': .95, 'external_prompting': .7}, const ['time', 'attention'], certainty: .95),
        _c(nodeId, 'selective', 'It is weirdly selective', 'Some things stick forever and others evaporate.', const {'memory_support_need': .4, 'emotional_sensitivity': .2}, const ['attention', 'values_goals'], certainty: .5),
      ];
    case 'attention':
      return [
        _c(nodeId, 'lock', 'I can lock in hard', 'If it grabs me, the rest of the world can disappear.', const {'focus_depth': .9, 'novelty_preference': .4}, const ['task_start', 'sensory'], certainty: .95),
        _c(nodeId, 'setup', 'I focus with the right setup', 'Environment and structure matter a lot.', const {'focus_depth': .4, 'structure_need': .5, 'sensory_sensitivity': .4}, const ['sensory', 'structure'], certainty: .85),
        _c(nodeId, 'stolen', 'My attention gets stolen easily', 'Small interruptions can knock me off course.', const {'focus_depth': -.7, 'external_prompting': .4}, const ['sensory', 'memory', 'time'], certainty: .95),
        _c(nodeId, 'swings', 'It swings wildly', 'Some days laser, some days pinball.', const {'focus_depth': 0, 'emotional_sensitivity': .3}, const ['stress', 'motivation'], certainty: .45),
      ];
    case 'time':
      return [
        _c(nodeId, 'solid', 'My clock is solid', 'I usually know what time is doing.', const {'time_horizon': .7, 'conscientiousness': .4}, const ['structure'], certainty: .95),
        _c(nodeId, 'anchors', 'I need visible anchors', 'Timers and checkpoints keep time real.', const {'time_horizon': .1, 'external_prompting': .6}, const ['memory', 'structure'], certainty: .9),
        _c(nodeId, 'lies', 'Time absolutely lies to me', 'Minutes and hours are not trustworthy objects.', const {'time_horizon': -.8, 'external_prompting': .8}, const ['memory', 'task_start'], certainty: .95),
        _c(nodeId, 'depends', 'Depends what I am doing', 'Interesting things bend time more than boring ones.', const {'time_horizon': -.2, 'novelty_preference': .4}, const ['attention', 'motivation'], certainty: .5),
      ];
    case 'motivation':
      return [
        _c(nodeId, 'meaning', 'Meaning moves me', 'If I care why it matters, I can push.', const {'autonomy_need': .5, 'intrinsic_motivation': .9}, const ['values_goals', 'autonomy'], certainty: .95),
        _c(nodeId, 'urgency', 'Urgency moves me', 'A real clock or consequence wakes me up.', const {'urgency_motivation': .9, 'task_initiation': -.2}, const ['time', 'task_start'], certainty: .95),
        _c(nodeId, 'people', 'People move me', 'Accountability, teamwork, or not letting someone down works.', const {'relatedness_need': .7, 'external_prompting': .7}, const ['relatedness', 'communication'], certainty: .9),
        _c(nodeId, 'novelty', 'Novelty moves me', 'Fresh, interesting, challenging beats important-but-stale.', const {'novelty_preference': .9, 'openness': .5}, const ['openness', 'attention'], certainty: .9),
      ];
    case 'autonomy':
      return [
        _c(nodeId, 'ask', 'Ask me, then help', 'I want the final call but I like strong support.', const {'autonomy_need': .7, 'directness_preference': .3}, const ['communication', 'decision'], certainty: .9),
        _c(nodeId, 'tell', 'Just tell me what you think', 'Direct recommendations save me energy.', const {'autonomy_need': .2, 'directness_preference': .8}, const ['communication', 'decision'], certainty: .9),
        _c(nodeId, 'options', 'Give me options', 'I want to choose from a few good paths.', const {'autonomy_need': .8, 'decision_support_need': .5}, const ['decision'], certainty: .95),
        _c(nodeId, 'backoff', 'Back off if I push back', 'Pressure can make me resist even good advice.', const {'autonomy_need': .95, 'reactance': .8}, const ['conflict', 'communication'], certainty: .95),
      ];
    case 'competence':
      return [
        _c(nodeId, 'figure', 'Let me figure it out', 'Solving it myself makes it stick.', const {'competence_need': .7, 'autonomy_need': .5}, const ['autonomy', 'openness'], certainty: .9),
        _c(nodeId, 'example', 'Show me an example', 'I learn fastest when I can see what right looks like.', const {'competence_need': .6, 'structure_need': .5}, const ['structure', 'communication'], certainty: .9),
        _c(nodeId, 'wins', 'Break it into wins', 'Progress matters more than a giant explanation.', const {'competence_need': .9, 'external_prompting': .3}, const ['motivation', 'task_start'], certainty: .95),
        _c(nodeId, 'close', 'Stay close until I get it', 'I do better with support while confidence builds.', const {'competence_need': .8, 'relatedness_need': .5}, const ['relatedness', 'communication'], certainty: .9),
      ];
    case 'relatedness':
      return [
        _c(nodeId, 'fuel', 'People are fuel', 'Connection usually helps me function better.', const {'relatedness_need': .9, 'extraversion': .4}, const ['social_energy', 'attachment_support'], certainty: .95),
        _c(nodeId, 'few', 'A few people matter deeply', 'Quality beats quantity by a mile.', const {'relatedness_need': .7, 'extraversion': -.2}, const ['attachment_support', 'communication'], certainty: .9),
        _c(nodeId, 'solo', 'I need a lot of solo space', 'Connection matters, but I recover alone.', const {'relatedness_need': .2, 'extraversion': -.7}, const ['social_energy', 'sensory'], certainty: .9),
        _c(nodeId, 'state', 'It changes with my state', 'Sometimes I need people, sometimes I need everyone gone.', const {'relatedness_need': .4, 'emotional_sensitivity': .3}, const ['emotion', 'stress'], certainty: .45),
      ];
    case 'social_energy':
      return [
        _c(nodeId, 'charge', 'People charge me up', 'I usually leave interaction with more energy.', const {'extraversion': .9}, const ['relatedness', 'communication'], certainty: .95),
        _c(nodeId, 'one', 'One-on-one is my sweet spot', 'Depth is easier than a room full of humans.', const {'extraversion': -.2, 'relatedness_need': .6}, const ['relatedness', 'attachment_support'], certainty: .9),
        _c(nodeId, 'drain', 'People drain the battery', 'Even good social time costs energy.', const {'extraversion': -.8, 'sensory_sensitivity': .3}, const ['sensory', 'stress'], certainty: .95),
        _c(nodeId, 'people', 'Depends on the people', 'The room matters more than the headcount.', const {'extraversion': 0, 'relatedness_need': .4}, const ['communication', 'attachment_support'], certainty: .5),
      ];
    case 'communication':
      return [
        _c(nodeId, 'straight', 'Say it straight', 'Clarity matters more than cushioning.', const {'directness_preference': .95}, const ['conflict', 'autonomy'], certainty: .95),
        _c(nodeId, 'warm', 'Be warm but clear', 'I want honesty without sounding cold.', const {'directness_preference': .5, 'relatedness_need': .4}, const ['emotion', 'relatedness'], certainty: .9),
        _c(nodeId, 'talk', 'Talk it through with me', 'I understand things better through back-and-forth.', const {'reflection_preference': .7, 'relatedness_need': .5}, const ['emotion', 'decision'], certainty: .9),
        _c(nodeId, 'moment', 'Match the moment', 'My preferred tone changes with what is happening.', const {'directness_preference': .1, 'emotional_sensitivity': .3}, const ['stress', 'decision'], certainty: .5),
      ];
    case 'emotion':
      return [
        _c(nodeId, 'fast', 'I know fast', 'I can usually name what I am feeling pretty quickly.', const {'emotional_awareness': .9, 'reflection_preference': .3}, const ['communication'], certainty: .95),
        _c(nodeId, 'talk', 'I need to talk it out', 'The feeling becomes clear while I am expressing it.', const {'emotional_awareness': .4, 'reflection_preference': .8, 'relatedness_need': .4}, const ['relatedness', 'communication'], certainty: .9),
        _c(nodeId, 'time', 'I need time first', 'I understand feelings better after some distance.', const {'emotional_awareness': .2, 'reflection_preference': .5}, const ['stress', 'attachment_support'], certainty: .9),
        _c(nodeId, 'body', 'It hits before I can name it', 'My body or reaction often knows before my words do.', const {'emotional_awareness': -.3, 'emotional_sensitivity': .8}, const ['stress', 'sensory'], certainty: .95),
      ];
    case 'stress':
      return [
        _c(nodeId, 'speed', 'I speed up', 'I start doing everything faster and less cleanly.', const {'stress_activation': .8, 'emotional_sensitivity': .5}, const ['time', 'attention'], certainty: .95),
        _c(nodeId, 'freeze', 'I freeze', 'Knowing what to do does not mean I can move.', const {'stress_activation': -.8, 'task_initiation': -.6}, const ['task_start', 'competence'], certainty: .95),
        _c(nodeId, 'scatter', 'I scatter', 'My brain opens twelve tabs and finishes none.', const {'stress_activation': .3, 'focus_depth': -.6}, const ['attention', 'structure'], certainty: .95),
        _c(nodeId, 'quiet', 'I go quiet', 'I pull inward and need room before I can engage.', const {'stress_activation': -.4, 'relatedness_need': .1}, const ['attachment_support', 'emotion'], certainty: .9),
      ];
    case 'conflict':
      return [
        _c(nodeId, 'now', 'Talk now', 'Unresolved tension eats more energy than the conversation.', const {'conflict_approach': .8, 'directness_preference': .6}, const ['communication', 'attachment_support'], certainty: .95),
        _c(nodeId, 'minute', 'Give me a minute', 'I need a cooldown before I can be fair.', const {'conflict_approach': .1, 'reflection_preference': .6}, const ['emotion', 'stress'], certainty: .9),
        _c(nodeId, 'avoid', 'I avoid it too long', 'I can delay conflict even when it is costing me.', const {'conflict_approach': -.8, 'agreeableness': .4}, const ['autonomy', 'attachment_support'], certainty: .95),
        _c(nodeId, 'who', 'Depends who it is', 'Safety and trust completely change my conflict style.', const {'conflict_approach': 0, 'relatedness_need': .4}, const ['attachment_support', 'relatedness'], certainty: .5),
      ];
    case 'attachment_support':
      return [
        _c(nodeId, 'toward', 'I reach toward people', 'Distance makes me want contact or reassurance.', const {'reassurance_preference': .8, 'relatedness_need': .7}, const ['relatedness', 'communication'], certainty: .95),
        _c(nodeId, 'inward', 'I pull inward', 'When hurt or uncertain, I usually want space.', const {'reassurance_preference': -.6, 'avoidance_preference': .7}, const ['autonomy', 'emotion'], certainty: .95),
        _c(nodeId, 'both', 'Reassurance, then space', 'Connection first helps me settle enough to think.', const {'reassurance_preference': .5, 'avoidance_preference': .2}, const ['emotion', 'communication'], certainty: .85),
        _c(nodeId, 'depends', 'Depends on the relationship', 'Different people bring out different patterns.', const {'reassurance_preference': .1, 'avoidance_preference': .1}, const ['relatedness', 'conflict'], certainty: .45),
      ];
    case 'openness':
      return [
        _c(nodeId, 'weird', 'Show me the weird idea', 'New possibilities are energizing.', const {'openness': .95, 'novelty_preference': .8}, const ['motivation', 'decision'], certainty: .95),
        _c(nodeId, 'reason', 'New is good with a reason', 'I will experiment if it makes sense.', const {'openness': .5, 'competence_need': .3}, const ['competence', 'decision'], certainty: .9),
        _c(nodeId, 'familiar', 'Familiar is calming', 'I prefer known systems unless there is a clear payoff.', const {'openness': -.5, 'structure_need': .5}, const ['structure', 'values_goals'], certainty: .9),
        _c(nodeId, 'stakes', 'Depends on the stakes', 'I experiment freely when failure is cheap.', const {'openness': .3, 'risk_tolerance': .2}, const ['decision', 'competence'], certainty: .5),
      ];
    case 'sensory':
      return [
        _c(nodeId, 'everything', 'I notice everything', 'Sound, light, texture, or clutter can hit hard.', const {'sensory_sensitivity': .95}, const ['stress', 'attention'], certainty: .95),
        _c(nodeId, 'specific', 'A few things get me', 'Specific sensory triggers matter more than general sensitivity.', const {'sensory_sensitivity': .5}, const ['attention'], certainty: .85),
        _c(nodeId, 'little', 'Usually not a big factor', 'Environment rarely decides whether I can function.', const {'sensory_sensitivity': -.7}, const ['attention'], certainty: .95),
        _c(nodeId, 'overload', 'Only when overloaded', 'Sensory stuff gets louder when stress is already high.', const {'sensory_sensitivity': .3, 'emotional_sensitivity': .4}, const ['stress', 'emotion'], certainty: .85),
      ];
    case 'decision':
      return [
        _c(nodeId, 'fast', 'Pick fast and adjust', 'I would rather move than optimize forever.', const {'decision_speed': .9, 'risk_tolerance': .5}, const ['autonomy', 'openness'], certainty: .95),
        _c(nodeId, 'few', 'Give me a few good options', 'Too many possibilities create drag.', const {'decision_speed': .3, 'decision_support_need': .7}, const ['autonomy', 'structure'], certainty: .9),
        _c(nodeId, 'think', 'I want to think it through', 'Important choices deserve research and comparison.', const {'decision_speed': -.5, 'conscientiousness': .5}, const ['competence', 'values_goals'], certainty: .95),
        _c(nodeId, 'stuck', 'I get stuck choosing', 'Even small choices can eat more energy than they should.', const {'decision_speed': -.9, 'decision_support_need': .9}, const ['structure', 'stress'], certainty: .95),
      ];
    case 'values_goals':
      return [
        _c(nodeId, 'people', 'Relationships', 'People and connection are a major compass.', const {'relatedness_need': .9, 'value_relationships': .9}, const ['relatedness', 'attachment_support'], certainty: .95),
        _c(nodeId, 'growth', 'Growth and achievement', 'Building something or becoming better matters a lot.', const {'competence_need': .8, 'value_growth': .9}, const ['competence', 'motivation'], certainty: .95),
        _c(nodeId, 'freedom', 'Freedom and possibility', 'I care a lot about room to choose and explore.', const {'autonomy_need': .9, 'openness': .6, 'value_freedom': .9}, const ['autonomy', 'openness'], certainty: .95),
        _c(nodeId, 'stability', 'Stability and peace', 'A life that feels safe and sustainable matters most.', const {'structure_need': .7, 'value_stability': .9}, const ['structure', 'stress'], certainty: .95),
      ];
    default:
      return [
        _c(nodeId, 'yes', 'That sounds like me', 'This fits pretty well.', const {}, const [], certainty: .9),
        _c(nodeId, 'somewhat', 'Somewhat', 'Part of it fits, part does not.', const {}, const [], certainty: .6),
        _c(nodeId, 'no', 'Not really', 'This does not describe me well.', const {}, const [], certainty: .9),
        _c(nodeId, 'depends', 'It depends', 'Context changes the answer.', const {}, const [], certainty: .4),
      ];
  }
}
