//
//  LucidContent.swift
//  HalfLight
//
//  The lucid-dreaming curriculum: the full text content for every lesson, grouped
//  into nine sections that form the lesson path. Pure data — the lesson UI
//  (`LucidLessonView`) renders it and `LucidProgress` tracks completion.
//
//  Tone: calm, dreamy, grounded. Responsible, beginner-friendly, never overpromising.
//

import Foundation

/// A single multiple-choice check inside a lesson.
struct LucidQuiz {
    let question: String
    let options: [String]
    /// Index into `options` of the correct answer.
    let answer: Int
    /// One line explaining why the answer is right (shown after answering).
    let why: String
}

/// The full content of one lesson, rendered as a short stepped flow.
struct LucidLessonContent: Identifiable {
    let id: String
    let title: String
    let icon: String
    /// A one-line curiosity hook shown on the intro step.
    let hook: String
    /// The core explanation (1–3 short sentences).
    let teach: String
    let quiz: LucidQuiz
    /// A reflective prompt the dreamer can answer in their head or in a field.
    let reflection: String
    /// A tiny, do-it-today challenge.
    let challenge: String
    /// The rewarding completion message.
    let done: String
    /// An optional closing "dreamer tip".
    let tip: String
    /// An optional "Did you know?" fact shown on the intro step to add depth and
    /// grounding. Kept accurate and responsible; empty hides the card.
    var didYouKnow: String = ""

    /// Every lesson grants the same XP, wired into the existing lucid economy.
    var xp: Int { DreamProgression.xpPerLucidSection }
}

/// A group of lessons belonging to one method or theme.
struct LucidSectionContent: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let icon: String
    let lessons: [LucidLessonContent]
}

/// The whole curriculum, top to bottom.
enum LucidCurriculum {
    static let sections: [LucidSectionContent] = [
        foundations, dreamRecall, realityChecks, mild, wbtb, wild,
        stabilization, commonProblems, advanced
    ]

    /// Every lesson flattened in path order — used to compute unlock status.
    static let allLessons: [LucidLessonContent] = sections.flatMap(\.lessons)

    static func lesson(id: String) -> LucidLessonContent? {
        allLessons.first { $0.id == id }
    }

    // MARK: - 1. Foundations

    private static let foundations = LucidSectionContent(
        id: "foundations",
        title: "Foundations",
        subtitle: "The awareness habits every method relies on",
        icon: "moon.stars.fill",
        lessons: [
            LucidLessonContent(
                id: "foundations-1",
                title: "What Is Lucid Dreaming?",
                icon: "sparkles",
                hook: "Tonight, while your body sleeps, part of your mind can quietly wake up. Most people never notice it.",
                teach: "A lucid dream is simply a dream in which you realize you're dreaming. No magic, no leaving your body — just a flicker of awareness inside sleep. The moment you know, the dream becomes a place you can explore, and sometimes shape. It's a real, studied state: about half of people have had one by accident.",
                quiz: LucidQuiz(
                    question: "Which of these is a lucid dream?",
                    options: [
                        "A dream so vivid you remember it all day",
                        "A dream where you realize, mid-dream, that you're dreaming",
                        "A dream you can't remember at all"
                    ],
                    answer: 1,
                    why: "Lucidity is defined by one thing: awareness that you're dreaming."
                ),
                reflection: "If you woke up inside a dream right now and knew it was yours — where's the first place you'd go?",
                challenge: "Say one sentence out loud before bed: \"Tonight, I'll notice I'm dreaming.\" Belief is the first skill.",
                done: "You've named the door most people walk past every night. It's real — and now you know it's there.",
                tip: "Lucidity is a skill, not luck. Skills grow with reps — and you just took your first.",
                didYouKnow: "Lucid dreaming was first verified in a sleep lab in 1975: a dreaming volunteer signaled \"I know I'm dreaming\" using pre-agreed eye movements, while the rest of the body stayed paralyzed in REM. It's been studied seriously ever since."
            ),
            LucidLessonContent(
                id: "foundations-2",
                title: "The Science Behind the Magic",
                icon: "waveform.path.ecg",
                hook: "Your most vivid dreams happen at a very specific time of night. Know when, and you know where to aim.",
                teach: "Sleep moves in cycles of about 90 minutes. Near the end of each one you enter REM sleep — the stage where the brain lights up almost like it's awake, and your richest dreams live. Crucially, REM gets longer toward morning, so your last few hours of sleep are dense with dream time.",
                quiz: LucidQuiz(
                    question: "When are your longest, most vivid dreams most likely?",
                    options: [
                        "The moment you fall asleep",
                        "In the hours just before you wake up",
                        "Evenly all night long"
                    ],
                    answer: 1,
                    why: "REM periods grow longer toward morning — that's prime dreaming territory."
                ),
                reflection: "Think of a dream you actually remember. Was it closer to bedtime, or closer to your alarm?",
                challenge: "Notice your natural wake-up time tomorrow. That early, drowsy window is dreaming gold we'll use later.",
                done: "You've learned the rhythm of the night. Skilled dreamers work with this tide, not against it.",
                tip: "You don't need more sleep to lucid dream — you need awareness during the sleep you already get.",
                didYouKnow: "Across a full night you spend roughly two hours in dreams — but because REM stretches longer with each cycle, your final cycle before waking can hold a single dream lasting close to an hour."
            ),
            LucidLessonContent(
                id: "foundations-3",
                title: "The Dreamer's Mindset",
                icon: "leaf.fill",
                hook: "Two people use the same technique. The one who expects it to work usually gets there first.",
                teach: "Lucid dreaming lives where intention meets attention. Intention is wanting it gently and consistently. Attention is the habit of questioning your reality, which slowly leaks into your dreams. The biggest beginner mistake is trying hard for one night, then quitting. Treat it like watering a plant: small, calm, daily.",
                quiz: LucidQuiz(
                    question: "What's the healthiest mindset for learning?",
                    options: [
                        "Force it as hard as possible tonight",
                        "Calm, curious, and consistent over time",
                        "Only try on weekends"
                    ],
                    answer: 1,
                    why: "Gentle repetition trains the dreaming mind far better than pressure."
                ),
                reflection: "What's one small thing you can do every day this week to stay curious about your dreams?",
                challenge: "Decide where and when you'll keep a dream journal — by your bed, on waking. Choosing the moment is half the habit.",
                done: "Foundations complete. You understand what lucidity is, when it lives, and the mindset that unlocks it.",
                tip: "Streaks beat effort. One calm minute a day out-trains an hour of frustration.",
                didYouKnow: "Expectation is measurable: studies find that people who simply believe they're likely to have a lucid dream tonight go on to have more of them. Your mindset isn't a side note — it's part of the technique."
            )
        ]
    )

    // MARK: - 2. Dream Recall

    private static let dreamRecall = LucidSectionContent(
        id: "recall",
        title: "Dream Recall",
        subtitle: "You can't wake up in a dream you forget",
        icon: "book.fill",
        lessons: [
            LucidLessonContent(
                id: "recall-1",
                title: "Why Dreams Vanish",
                icon: "wind",
                hook: "You dream every night — four to six times. So why does morning feel so empty?",
                teach: "The brain barely saves dreams to long-term memory; they fade within minutes of waking unless you catch them. This isn't a flaw you're stuck with — recall is a muscle. People who decide to remember their dreams start remembering far more within days.",
                quiz: LucidQuiz(
                    question: "Why don't most people remember their dreams?",
                    options: [
                        "They don't actually dream",
                        "Dreams aren't saved to memory unless you catch them quickly",
                        "Only some people can dream"
                    ],
                    answer: 1,
                    why: "Everyone dreams nightly — the memories just fade fast without effort to keep them."
                ),
                reflection: "When did you last remember a dream? What was the feeling it left behind?",
                challenge: "Tonight, as you fall asleep, repeat: \"I will remember my dreams.\" Intention primes recall.",
                done: "You've learned the first secret: dreams aren't gone, just uncaught. Tomorrow, you start catching them.",
                tip: "Recall is the foundation of everything. No technique works without it.",
                didYouKnow: "Dreams fade fast because the brain chemistry that stores long-term memories is largely switched off during REM. The memory isn't deleted — it was barely written down in the first place, so catching it quickly is everything."
            ),
            LucidLessonContent(
                id: "recall-2",
                title: "The Dream Journal",
                icon: "square.and.pencil",
                hook: "The first 60 seconds after waking decide whether a dream survives the day.",
                teach: "Keep something to write with right where you wake. The instant you stir, record whatever you have — words, images, a single feeling. Don't judge it, don't wait. Writing it down tells your brain dreams matter, and recall snowballs from there.",
                quiz: LucidQuiz(
                    question: "When should you record a dream?",
                    options: [
                        "Whenever you get around to it",
                        "Immediately on waking, before doing anything else",
                        "Only if it was a good dream"
                    ],
                    answer: 1,
                    why: "Dreams evaporate fast — capture them in the first moments, every time."
                ),
                reflection: "What gets in the way of writing first thing — your phone, getting up, rushing? How could you remove it?",
                challenge: "Log your very next dream in HalfLight the moment you wake — even if it's one word.",
                done: "Your dream journal is open. Every entry sharpens the next morning's memory.",
                tip: "Even \"I remember nothing\" counts — write that. It keeps the habit alive.",
                didYouKnow: "Keeping a dream journal is one of the few habits shown in research to reliably increase both how much you recall and how often you become lucid. The simple act of writing tells your brain that dreams are worth keeping."
            ),
            LucidLessonContent(
                id: "recall-3",
                title: "Catching the Fragments",
                icon: "scribble.variable",
                hook: "\"I only remember a feeling.\" Good — that feeling is a thread you can pull.",
                teach: "Recall rarely arrives whole. You'll get a mood, a color, a face, a place. Write the fragment first, then gently ask: what came before this? Often one detail unspools several more. Never dismiss a scrap as too small.",
                quiz: LucidQuiz(
                    question: "You wake with only a vague feeling. What do you do?",
                    options: [
                        "Ignore it — it's not a real dream",
                        "Write the fragment, then let more details unspool from it",
                        "Force yourself to invent the rest"
                    ],
                    answer: 1,
                    why: "A single fragment is a thread — pulling it gently often reveals more."
                ),
                reflection: "What's the smallest dream detail you've ever remembered? Could you have pulled more from it?",
                challenge: "Next waking, lie still and name one detail before reaching for anything. Then write it.",
                done: "You're learning to fish in the fog. Fragments today become full dreams tomorrow.",
                tip: "Stay in the dream's posture — sometimes returning to how you were lying brings it back.",
                didYouKnow: "Memory works by association, so a single fragment is a real handle: re-feeling the dream's mood or picturing its one clear image often cues the surrounding scene back into view, like pulling a thread."
            ),
            LucidLessonContent(
                id: "recall-4",
                title: "Wake Gently",
                icon: "sunrise.fill",
                hook: "Most people delete their dreams in the first three seconds — by moving too fast.",
                teach: "When you wake, stay still with your eyes closed for a moment. Don't jump up, don't grab your phone. Let the dream linger in that half-light. Replaying it once or twice in your mind before moving makes it far more likely to survive.",
                quiz: LucidQuiz(
                    question: "What's the best first move on waking?",
                    options: [
                        "Check your phone right away",
                        "Stay still, eyes closed, and replay the dream",
                        "Get up quickly to start the day"
                    ],
                    answer: 1,
                    why: "Stillness on waking keeps the dream from scattering before you can hold it."
                ),
                reflection: "What's the first thing you usually do when you wake? Is it helping or erasing your dreams?",
                challenge: "Tomorrow, don't move for 30 seconds after waking. Just replay the night, then write.",
                done: "You've learned the gentlest, most powerful recall trick there is: stillness.",
                tip: "Set a calm alarm tone — jarring alarms blast dreams out of memory.",
                didYouKnow: "Waking gently keeps you near the dream state long enough to copy it into memory. A jarring alarm floods you with alertness and stress hormones that scatter the dream before you can catch it."
            ),
            LucidLessonContent(
                id: "recall-5",
                title: "Spotting Dream Signs",
                icon: "eye.trianglebadge.exclamationmark.fill",
                hook: "Your dreams repeat themselves. Those patterns are secret alarms that say: you're dreaming.",
                teach: "Read back through your journal and you'll find recurring themes — a certain place, person, feeling, or impossible event. These are your dream signs. Learning to recognize them is huge: when one shows up, it can trigger the realization that you're dreaming.",
                quiz: LucidQuiz(
                    question: "What's a \"dream sign\"?",
                    options: [
                        "A sign you slept well",
                        "A recurring theme in your dreams that can trigger lucidity",
                        "A symbol that predicts the future"
                    ],
                    answer: 1,
                    why: "Recognizing your personal recurring patterns is a doorway to becoming lucid."
                ),
                reflection: "Looking back, what shows up again and again in your dreams?",
                challenge: "Review your journal entries and mark one recurring dream sign to watch for.",
                done: "Recall mastered. You're catching dreams and reading their patterns — the raw material of lucidity.",
                tip: "When a dream sign appears in waking life too, do a reality check. That bridge is gold.",
                didYouKnow: "Dream signs are personal — one dreamer's recurring theme might be losing teeth, another's a childhood house. Cataloguing your own is one of the most powerful, individualized routes to lucidity there is."
            )
        ]
    )

    // MARK: - 3. Reality Checks

    private static let realityChecks = LucidSectionContent(
        id: "checks",
        title: "Reality Checks",
        subtitle: "Train a habit awake, and it follows you into the dream",
        icon: "hand.raised.fill",
        lessons: [
            LucidLessonContent(
                id: "checks-1",
                title: "What Is a Reality Check?",
                icon: "questionmark.circle.fill",
                hook: "What if the simplest way to wake up inside a dream is a habit you build while awake?",
                teach: "A reality check is a quick test of whether you're dreaming, done throughout your day. In dreams, reality behaves strangely — so a test that fails in waking life will reveal a dream. Do it often enough awake and you'll do it in a dream too, and catch the strangeness.",
                quiz: LucidQuiz(
                    question: "Why do reality checks work?",
                    options: [
                        "They wake you from real life",
                        "A daytime habit carries into dreams, where the test reveals you're dreaming",
                        "They make you fall asleep faster"
                    ],
                    answer: 1,
                    why: "The habit follows you into the dream, where reality fails the test."
                ),
                reflection: "How often during the day do you truly question whether you're awake? (Almost never, right?)",
                challenge: "Right now, genuinely ask: \"Am I dreaming?\" — and mean it. That's your first check.",
                done: "You've learned the bridge between waking and dreaming. Next, we pick your tool.",
                tip: "The question matters more than the test. Always ask it like the answer could surprise you.",
                didYouKnow: "Reality testing was popularized by lucid-dream researcher Stephen LaBerge as a way to make critical, questioning awareness so automatic that it shows up on its own inside a dream."
            ),
            LucidLessonContent(
                id: "checks-2",
                title: "Choosing Your Check",
                icon: "hand.point.up.left.fill",
                hook: "Some reality checks fail almost every time in a dream. Here are the most reliable.",
                teach: "Pick one or two: push a finger against your palm (it often passes through in dreams); pinch your nose and try to breathe (you still can in a dream); read text, look away, read again (it usually changes). Reliable, physical, and easy to repeat.",
                quiz: LucidQuiz(
                    question: "Which is a strong reality check?",
                    options: [
                        "Pinching your nose and trying to breathe",
                        "Wishing really hard",
                        "Closing your eyes and counting"
                    ],
                    answer: 0,
                    why: "In a dream you can often still 'breathe' with your nose pinched — a clear giveaway."
                ),
                reflection: "Which check feels most natural to you — hands, breath, or reading?",
                challenge: "Choose your reality check now and do it three times today.",
                done: "You've got your tool. A simple, repeatable test you can carry everywhere.",
                tip: "Pick checks you can do anywhere without looking odd — you'll do them more.",
                didYouKnow: "The nose-pinch check is reliable because your real airway is irrelevant inside a dream — there's no physical block, so your dreaming mind simply lets you keep \"breathing.\" That impossible breath is the tell."
            ),
            LucidLessonContent(
                id: "checks-3",
                title: "Doing It Right",
                icon: "exclamationmark.triangle.fill",
                hook: "Most reality checks fail for one silly reason: you did them on autopilot.",
                teach: "A check only works if you actually expect it might reveal a dream. Doing it mindlessly trains nothing. Pause, look around, truly consider \"could this be a dream?\", then run the test and watch the result with genuine curiosity.",
                quiz: LucidQuiz(
                    question: "What makes a reality check actually work?",
                    options: [
                        "Doing it as fast as possible",
                        "Genuinely expecting it might reveal a dream",
                        "Doing it exactly 10 times"
                    ],
                    answer: 1,
                    why: "Mindless checks train nothing — real curiosity is what carries into dreams."
                ),
                reflection: "Have you ever done something on autopilot and missed the obvious? How do you stay present?",
                challenge: "Do one reality check today where you truly pause and expect a surprise.",
                done: "You now check with intention, not habit-on-autopilot. That's the difference that matters.",
                tip: "If you ever 'pass' a check oddly, look closer — that's exactly the dream moment to notice.",
                didYouKnow: "Text and digital clocks are famously unstable in dreams: look away and back and they often change. The dreaming brain renders the gist of a scene, not its fine detail, so re-reading anything tends to reshuffle it."
            ),
            LucidLessonContent(
                id: "checks-4",
                title: "Anchors & Triggers",
                icon: "bell.badge.fill",
                hook: "What if your front door reminded you to check reality — every single time?",
                teach: "Tie your checks to things you encounter often: doorways, mirrors, phones, or your personal dream signs. These anchors turn random moments into reliable reminders, so the habit runs itself instead of relying on memory.",
                quiz: LucidQuiz(
                    question: "What's a good reality-check anchor?",
                    options: [
                        "Something you rarely encounter",
                        "Everyday triggers like doorways, mirrors, or your dream signs",
                        "Only your alarm in the morning"
                    ],
                    answer: 1,
                    why: "Frequent, predictable cues turn checks into an automatic habit."
                ),
                reflection: "What's something you pass through or look at dozens of times a day?",
                challenge: "Pick one anchor (say, every doorway) and reality-check each time you meet it today.",
                done: "Your day is now dotted with triggers. The habit is starting to run on its own.",
                tip: "Anchor to your dream signs especially — they're most likely to appear in dreams too.",
                didYouKnow: "Habit research shows that behaviors tied to an existing cue — a doorway, a mirror, unlocking your phone — stick far better than ones you have to remember from scratch. You're borrowing triggers your day already has."
            ),
            LucidLessonContent(
                id: "checks-5",
                title: "The All-Day Habit",
                icon: "infinity",
                hook: "The goal isn't 100 checks a day. It's the right kind, done with real attention.",
                teach: "Aim for 5–10 genuine reality checks daily, spread across your anchors. Done with curiosity, this rewires how you relate to reality — until one night, inside a dream, you check, the test fails, and you finally realize where you are.",
                quiz: LucidQuiz(
                    question: "How many quality reality checks should you aim for daily?",
                    options: [
                        "As many as possible, mindlessly",
                        "Around 5–10, done with genuine attention",
                        "Just one, right before bed"
                    ],
                    answer: 1,
                    why: "A handful of real, curious checks beats hundreds on autopilot."
                ),
                reflection: "Which moments in your day would make the most natural check-in points?",
                challenge: "Do 5 genuine reality checks today, each tied to an anchor.",
                done: "Reality Checks complete. You've built a waking habit that's quietly hunting for your dreams.",
                tip: "Pair this with MILD next — together they're one of the strongest combinations there is.",
                didYouKnow: "In formal studies, reality checks really shine when combined with other methods like MILD — layered habits consistently outperform any single technique used on its own."
            )
        ]
    )

    // MARK: - 4. MILD

    private static let mild = LucidSectionContent(
        id: "mild",
        title: "MILD",
        subtitle: "Mnemonic Induction of Lucid Dreams",
        icon: "brain.head.profile",
        lessons: [
            LucidLessonContent(
                id: "mild-1",
                title: "What MILD Means",
                icon: "brain.head.profile",
                hook: "Your memory can be set like an alarm — to go off inside a dream.",
                teach: "MILD uses prospective memory: remembering to do something in the future. You rehearse the intention to recognize you're dreaming, so that later, in a dream, the thought resurfaces. It's one of the most studied and effective induction techniques.",
                quiz: LucidQuiz(
                    question: "MILD is built on which mental skill?",
                    options: [
                        "Forgetting your day",
                        "Prospective memory — remembering to remember in the future",
                        "Counting sheep"
                    ],
                    answer: 1,
                    why: "MILD plants a future intention that resurfaces inside the dream."
                ),
                reflection: "When have you 'remembered to remember' something at just the right moment in waking life?",
                challenge: "Tonight, as you drift off, hold the thought: \"Next time I'm dreaming, I'll realize it.\"",
                done: "You've met MILD — turning memory itself into a doorway to lucidity.",
                tip: "MILD pairs perfectly with the reality-check habit you just built.",
                didYouKnow: "MILD was developed by Stephen LaBerge during his doctoral research at Stanford and remains one of the best-supported induction techniques in the scientific literature."
            ),
            LucidLessonContent(
                id: "mild-2",
                title: "The Lucid Phrase",
                icon: "text.quote",
                hook: "A single sentence, repeated with meaning, can become the key that turns inside a dream.",
                teach: "Craft a short intention and repeat it as you fall asleep: \"The next time I'm dreaming, I will remember that I'm dreaming.\" Say it slowly, mean it, and picture it working. The feeling behind the words matters as much as the words.",
                quiz: LucidQuiz(
                    question: "What makes the MILD phrase effective?",
                    options: [
                        "Saying it as fast as you can",
                        "Repeating it slowly, with genuine intention and belief",
                        "Saying it once and forgetting it"
                    ],
                    answer: 1,
                    why: "Meaning and belief charge the intention — empty repetition does little."
                ),
                reflection: "What wording feels most natural and convincing in your own voice?",
                challenge: "Write your personal lucid phrase and repeat it 10 times before sleep tonight.",
                done: "You've forged your key phrase. Words you'll carry across the threshold of sleep.",
                tip: "Keep it short enough to repeat without effort as you fade out.",
                didYouKnow: "The skill MILD trains — prospective memory, or remembering to do something later — is the same one that reminds you to grab milk on the way home. MILD just aims that everyday ability at the dream world."
            ),
            LucidLessonContent(
                id: "mild-3",
                title: "Visualize the Moment",
                icon: "eye.fill",
                hook: "Don't just say you'll become lucid — rehearse the exact moment until it feels real.",
                teach: "As you repeat your phrase, picture a recent dream and imagine realizing, inside it, that you're dreaming. See yourself doing a reality check and the dream snapping into clarity. This mental rehearsal makes the real moment far more likely.",
                quiz: LucidQuiz(
                    question: "What should you visualize during MILD?",
                    options: [
                        "A blank screen",
                        "Becoming lucid inside a recent dream, doing a reality check",
                        "Your to-do list"
                    ],
                    answer: 1,
                    why: "Rehearsing the moment of realization trains your mind to actually have it."
                ),
                reflection: "Pick a recent dream. Where in it would realizing 'I'm dreaming' have been easiest?",
                challenge: "Tonight, replay a recent dream and imagine becoming lucid inside it.",
                done: "You've rehearsed the moment. Your mind now knows the shape of becoming lucid.",
                tip: "Use a real dream from your journal — familiarity makes the rehearsal vivid.",
                didYouKnow: "Mental rehearsal lights up many of the same brain regions as actually doing the thing — which is why athletes visualize their routines and why imagining the moment of lucidity helps train it."
            ),
            LucidLessonContent(
                id: "mild-4",
                title: "Timing MILD Right",
                icon: "clock.fill",
                hook: "The same technique works far better at 5am than at bedtime. Here's the catch.",
                teach: "MILD is strongest after a brief awakening in the early morning, when you fall back into REM-rich sleep. Practicing it as you return to sleep — rather than at the start of the night — dramatically raises your odds. (That's the bridge to WBTB, next.)",
                quiz: LucidQuiz(
                    question: "When does MILD work best?",
                    options: [
                        "Only at the very start of the night",
                        "After a brief wake-up in the early morning, returning to sleep",
                        "During the day"
                    ],
                    answer: 1,
                    why: "Returning to morning REM after a short waking is MILD's sweet spot."
                ),
                reflection: "Do you ever wake naturally in the early morning? Could you use that moment?",
                challenge: "If you wake during the night, repeat your lucid phrase as you fall back asleep.",
                done: "You've learned MILD's secret timing. Practice it near morning and watch it bloom.",
                tip: "Don't lose sleep chasing it — a natural night-waking is the perfect, free opportunity.",
                didYouKnow: "A 2017 study of MILD found it worked best when practiced right after a brief awakening — and that success climbed the faster people fell back asleep afterward, ideally within five minutes."
            ),
            LucidLessonContent(
                id: "mild-5",
                title: "Stacking the Odds",
                icon: "square.stack.3d.up.fill",
                hook: "No single technique is magic. Stacked together, they become hard to ignore.",
                teach: "The strongest routine layers what you've learned: strong recall, an all-day reality-check habit, and MILD with visualization as you fall asleep — ideally near morning. Each piece is small; together they tip the odds firmly in your favor.",
                quiz: LucidQuiz(
                    question: "What's the most effective approach?",
                    options: [
                        "Relying on one technique alone",
                        "Stacking recall, reality checks, and MILD together",
                        "Switching techniques every single night"
                    ],
                    answer: 1,
                    why: "Layered habits reinforce each other — that's where consistent results come from."
                ),
                reflection: "Which piece of your routine feels strongest right now? Which needs work?",
                challenge: "Tonight, do all three: journal-ready, a few reality checks today, and MILD at sleep.",
                done: "MILD complete. You can now aim your memory at the dream world — and stack the odds.",
                tip: "Consistency over intensity. A gentle stack done nightly beats a heroic effort once.",
                didYouKnow: "Researchers consistently find that no single induction method is reliable on its own — combining recall, reality checks, and MILD outperforms any one of them used alone. Stacking is the real technique."
            )
        ]
    )

    // MARK: - 5. WBTB

    private static let wbtb = LucidSectionContent(
        id: "wbtb",
        title: "WBTB",
        subtitle: "Wake Back to Bed",
        icon: "bed.double.fill",
        lessons: [
            LucidLessonContent(
                id: "wbtb-1",
                title: "What Is Wake Back to Bed?",
                icon: "bed.double.fill",
                hook: "The single biggest boost to your odds isn't a new skill — it's a clever bit of timing.",
                teach: "WBTB means waking briefly after several hours of sleep, staying up a short while, then going back to bed. You return to sleep straight into long, vivid REM with a more alert mind — the ideal conditions for lucidity, especially paired with MILD.",
                quiz: LucidQuiz(
                    question: "What does WBTB involve?",
                    options: [
                        "Staying awake all night",
                        "Waking after a few hours, briefly, then returning to sleep",
                        "Sleeping in much later than usual"
                    ],
                    answer: 1,
                    why: "A short waking before returning to REM-rich sleep is the whole technique."
                ),
                reflection: "How might a short, planned wake-up fit into your sleep — without wrecking it?",
                challenge: "Read tonight's plan: you'll set a gentle alarm for a few hours after bedtime.",
                done: "You've met the most powerful timing trick in lucid dreaming. Now we tune it.",
                tip: "WBTB amplifies every other technique — it's a multiplier, not a replacement.",
                didYouKnow: "REM periods lengthen as the night goes on: your first might last about ten minutes, while a pre-dawn one can run close to an hour. WBTB drops you straight back into that long, dream-rich window."
            ),
            LucidLessonContent(
                id: "wbtb-2",
                title: "Finding Your Wake Window",
                icon: "timer",
                hook: "Wake at the wrong hour and you'll just feel groggy. Wake at the right one and the dream world opens.",
                teach: "The sweet spot is usually 4.5–6 hours after falling asleep — late enough that REM is long, early enough that you can fall back asleep. Everyone's a little different, so experiment within that window and notice what leaves you alert-but-sleepy.",
                quiz: LucidQuiz(
                    question: "When's the typical WBTB wake window?",
                    options: [
                        "30 minutes after bed",
                        "About 4.5–6 hours after falling asleep",
                        "Right before your normal alarm"
                    ],
                    answer: 1,
                    why: "That window lands you between REM cycles, with rich dreaming still ahead."
                ),
                reflection: "If you fall asleep around your usual time, what clock time is ~5 hours later?",
                challenge: "Set a soft alarm for about 5 hours after you expect to fall asleep tonight.",
                done: "You've found your window. Timing turns ordinary sleep into a launchpad.",
                tip: "Adjust by 30 minutes over a few nights until you find your personal sweet spot.",
                didYouKnow: "The early-morning hours are so dense with REM that most spontaneous lucid dreams — the accidental ones people stumble into — happen close to their natural wake-up time."
            ),
            LucidLessonContent(
                id: "wbtb-3",
                title: "The 20-Minute Rule",
                icon: "hourglass",
                hook: "Stay up too long and you lose the dream. Too short and you stay asleep. There's a window.",
                teach: "When you wake, stay up just long enough to become genuinely alert — often 10–20 minutes. Do something calm and dream-related (read your journal, review your lucid phrase), then return to bed. Avoid bright screens that fully wake you.",
                quiz: LucidQuiz(
                    question: "How long should you stay awake during WBTB?",
                    options: [
                        "Just a couple of minutes",
                        "Long enough to be alert, often 10–20 minutes",
                        "An hour or more"
                    ],
                    answer: 1,
                    why: "Enough to raise awareness, not so much that you can't fall back asleep."
                ),
                reflection: "What calm, screen-free thing could you do during that short wake window?",
                challenge: "Plan your wake-window activity now — reading your journal is perfect.",
                done: "You've nailed the timing balance: awake enough to be aware, sleepy enough to return.",
                tip: "Keep lights dim. Bright light tells your brain it's morning and kills the plan.",
                didYouKnow: "Bright light suppresses melatonin and signals your body clock that it's daytime — which is exactly why a short, dim wake window raises awareness just enough without flipping you fully into morning mode."
            ),
            LucidLessonContent(
                id: "wbtb-4",
                title: "WBTB + MILD",
                icon: "link",
                hook: "This is the combination most lucid dreams are actually made of.",
                teach: "Pair them: wake in your window, stay up briefly, then do MILD — repeat your lucid phrase and visualize becoming lucid as you fall back into REM-rich sleep. Decades of dreamers (and research) point to this duo as the most reliable beginner method.",
                quiz: LucidQuiz(
                    question: "What's the classic high-success combo?",
                    options: [
                        "WBTB plus MILD",
                        "WBTB plus caffeine",
                        "MILD at the very start of the night only"
                    ],
                    answer: 0,
                    why: "Waking into REM and aiming your memory at it is the proven pairing."
                ),
                reflection: "Which part feels harder for you — the waking, or the falling back asleep with intention?",
                challenge: "Tonight, run the full combo once: WBTB window, brief wake, then MILD back to sleep.",
                done: "You've assembled the powerhouse method. Recall, checks, MILD, and timing — all in one night.",
                tip: "If it doesn't work the first time, that's normal. The combo rewards patient repetition.",
                didYouKnow: "WBTB combined with MILD is widely regarded as the most effective beginner-friendly induction method in the research — the brief waking sharpens your mind right as you re-enter the night's richest REM."
            ),
            LucidLessonContent(
                id: "wbtb-5",
                title: "Protecting Your Sleep",
                icon: "heart.fill",
                hook: "A lucid dream isn't worth a wrecked night. Real dreamers protect their rest first.",
                teach: "Don't do WBTB every night, especially if you're tired — a few times a week is plenty. Lucid dreaming should add to your life, not drain it. Good, consistent sleep actually improves your dreams and recall, so rest is part of the practice.",
                quiz: LucidQuiz(
                    question: "How often should beginners do WBTB?",
                    options: [
                        "Every single night, no matter what",
                        "A few times a week, and never when overtired",
                        "Only once ever"
                    ],
                    answer: 1,
                    why: "Protecting your sleep keeps the practice healthy and sustainable."
                ),
                reflection: "How do you feel after a poor night's sleep? Is it worth chasing a dream that costs that?",
                challenge: "Pick 2–3 nights this week for WBTB — and commit to resting fully on the others.",
                done: "WBTB complete. You can summon the dream world's best hours — responsibly.",
                tip: "Tired? Skip it. A rested mind dreams more vividly and remembers more anyway.",
                didYouKnow: "Chronically fragmenting your sleep harms memory, mood, and focus — the very faculties lucid dreaming depends on. Spacing WBTB out isn't just kind to yourself; it keeps the practice working."
            )
        ]
    )

    // MARK: - 6. WILD

    private static let wild = LucidSectionContent(
        id: "wild",
        title: "WILD",
        subtitle: "Wake Initiated Lucid Dreams",
        icon: "sparkles",
        lessons: [
            LucidLessonContent(
                id: "wild-1",
                title: "What Is WILD?",
                icon: "sparkles",
                hook: "Imagine staying awake in your mind while your body falls asleep — and stepping straight into a dream.",
                teach: "In WILD, you keep a thread of awareness as your body drifts off, crossing directly into a dream without losing consciousness. It can produce stunningly vivid lucid dreams — but it's advanced, takes practice, and works best after WBTB. Patience is everything here.",
                quiz: LucidQuiz(
                    question: "What makes WILD different?",
                    options: [
                        "You become lucid by realizing it later in a dream",
                        "You stay aware as you fall asleep and enter the dream directly",
                        "You stay fully awake all night"
                    ],
                    answer: 1,
                    why: "WILD crosses the threshold of sleep with awareness intact."
                ),
                reflection: "How do you feel about staying aware as you fall asleep — curious, nervous, both?",
                challenge: "Tonight, just observe how you normally fall asleep. Notice the drift, don't force it.",
                done: "You've met the most direct path into a dream. Advanced — but unforgettable when it lands.",
                tip: "WILD is easiest after WBTB, when your body is tired but your mind can stay alert.",
                didYouKnow: "WILD asks you to stay conscious through the wake-to-sleep transition — a narrow doorway almost everyone passes through every single night without ever noticing it."
            ),
            LucidLessonContent(
                id: "wild-2",
                title: "The Hypnagogic Drift",
                icon: "cloud.moon.fill",
                hook: "On the edge of sleep, colors, shapes, and sounds appear from nowhere. That's your doorway.",
                teach: "As you fall asleep, you pass through hypnagogia — drifting images, patterns, and sounds. In WILD you watch these gently, like a film, without grabbing at them. Letting them build naturally lets a full dream scene form around you.",
                quiz: LucidQuiz(
                    question: "What is hypnagogia?",
                    options: [
                        "A type of nightmare",
                        "The dreamlike images and sounds at the edge of sleep",
                        "A breathing technique"
                    ],
                    answer: 1,
                    why: "These edge-of-sleep sensations are the raw material WILD builds a dream from."
                ),
                reflection: "Have you ever noticed images or sounds drifting in as you fall asleep?",
                challenge: "Tonight, as you drift off, simply watch any images that appear — observe, don't grab.",
                done: "You've learned to read the threshold's signs. The doorway has a shape now.",
                tip: "If images vanish when you focus hard, soften your attention — watch from the corner of your mind.",
                didYouKnow: "Hypnagogia — the drifting imagery at sleep's edge — has long fascinated creatives. Edison and Salvador Dalí famously napped holding an object so it would fall and wake them, catching ideas from that exact half-dreaming state."
            ),
            LucidLessonContent(
                id: "wild-3",
                title: "Staying Calm at the Threshold",
                icon: "wind",
                hook: "The moment it starts working, most beginners get excited — and instantly wake up.",
                teach: "The threshold is delicate. Excitement, fear, or trying too hard pulls you back to waking. The skill is calm, passive attention: notice what's happening without reacting. Steady breathing and a relaxed 'let it come' attitude keep you on the path.",
                quiz: LucidQuiz(
                    question: "What most often ruins a WILD attempt?",
                    options: [
                        "Staying too calm",
                        "Getting excited or trying too hard at the threshold",
                        "Breathing slowly"
                    ],
                    answer: 1,
                    why: "Strong reactions snap you awake — calm, passive attention keeps you in."
                ),
                reflection: "What helps you stay calm when something exciting starts to happen?",
                challenge: "Practice 5 minutes of calm, passive breathing tonight — just watching, not reacting.",
                done: "You've learned the WILD dreamer's superpower: staying perfectly, gently calm.",
                tip: "Tell yourself 'whatever happens is fine.' Removing the stakes keeps you steady.",
                didYouKnow: "The threshold is fragile because excitement and fear both raise brain arousal toward waking. Calm isn't just a mood here — it's literally the brain state that keeps you sliding toward sleep instead of away from it."
            ),
            LucidLessonContent(
                id: "wild-4",
                title: "Sleep Paralysis, Demystified",
                icon: "moon.zzz.fill",
                hook: "Sometimes your body falls asleep before your mind. It feels strange — and it's completely harmless.",
                teach: "During REM your body is naturally paralyzed so you don't act out dreams. In WILD you may notice it: a heavy, can't-move feeling, sometimes with odd sensations. It's normal and safe. Stay calm, keep breathing, and let it pass — it's a sign you're close.",
                quiz: LucidQuiz(
                    question: "What is sleep paralysis during WILD?",
                    options: [
                        "A dangerous medical emergency",
                        "Your body's natural REM paralysis — harmless, and a sign you're close",
                        "Proof the technique failed"
                    ],
                    answer: 1,
                    why: "It's a normal, safe part of REM — often the doorstep of a WILD."
                ),
                reflection: "How do you usually respond to unfamiliar body sensations — tense up, or breathe through?",
                challenge: "Learn the calm response now: if you feel it, think \"this is normal, I'm safe,\" and relax.",
                done: "You've demystified the spookiest part of WILD. Knowledge turns fear into a green light.",
                tip: "You can always end it by wiggling a toe or finger. Knowing that makes staying calm easy.",
                didYouKnow: "Sleep paralysis is just REM atonia — your brain's normal safety switch that stops you from physically acting out dreams. Noticing it while still aware is harmless; it simply means body and mind fell asleep slightly out of sync."
            ),
            LucidLessonContent(
                id: "wild-5",
                title: "Entering the Dream Gently",
                icon: "door.left.hand.open",
                hook: "When a scene forms around you, the final move is the gentlest one of all.",
                teach: "As hypnagogia builds into a scene, don't lunge into it — let it solidify, then gently 'step in,' perhaps by imagining touching the ground or rubbing your hands. Once you're there, do a reality check to confirm and stabilize. You've arrived, fully aware.",
                quiz: LucidQuiz(
                    question: "How should you enter the forming dream?",
                    options: [
                        "Jump in as forcefully as possible",
                        "Let the scene solidify, then step in gently and reality-check",
                        "Open your eyes to check it's real"
                    ],
                    answer: 1,
                    why: "A gentle entry keeps the fragile scene intact; forcing it collapses it."
                ),
                reflection: "Why might 'gentle' be the hardest instruction when something amazing is forming?",
                challenge: "Tonight, if a scene forms, imagine gently touching the ground within it.",
                done: "WILD complete. You've learned to walk through the door of sleep with your eyes wide open.",
                tip: "Don't be discouraged by misses — WILD often takes many tries. Each attempt teaches you the threshold.",
                didYouKnow: "Even experienced practitioners count their WILD misses — falling fully asleep or waking up is the norm, not failure. Each attempt quietly trains your familiarity with the threshold until one night it holds."
            )
        ]
    )

    // MARK: - 7. Dream Stabilization

    private static let stabilization = LucidSectionContent(
        id: "stable",
        title: "Dream Stabilization",
        subtitle: "Becoming lucid is half the battle — staying is the other half",
        icon: "circle.hexagongrid.fill",
        lessons: [
            LucidLessonContent(
                id: "stable-1",
                title: "Why Lucid Dreams Collapse",
                icon: "exclamationmark.bubble.fill",
                hook: "You finally realize you're dreaming — and three seconds later you wake up. Why?",
                teach: "The instant of lucidity floods you with excitement, and excitement pulls you toward waking. The dream also fades if you don't engage your dream senses. The fix is counterintuitive: calm down and ground yourself in the dream instead of celebrating.",
                quiz: LucidQuiz(
                    question: "Why do new lucid dreamers often wake up immediately?",
                    options: [
                        "The dream runs out of energy",
                        "Excitement and lack of grounding pull them awake",
                        "It's impossible to stay lucid"
                    ],
                    answer: 1,
                    why: "Over-excitement is the number-one cause of the early 'wake-up rush.'"
                ),
                reflection: "How do you usually react to something thrilling? Could that reaction wake you?",
                challenge: "Rehearse your reaction now: \"I'm dreaming — stay calm, stay grounded.\"",
                done: "You've found the hidden trap. Knowing it is the first step to staying longer.",
                tip: "The calmer you are when lucidity hits, the longer the dream lasts.",
                didYouKnow: "The \"wake-up rush\" is physiological: the jolt of realizing you're dreaming spikes brain arousal toward waking. Calming yourself literally lowers that arousal and keeps you asleep — which is why the fix feels backwards."
            ),
            LucidLessonContent(
                id: "stable-2",
                title: "Ground Your Senses",
                icon: "hand.tap.fill",
                hook: "The fastest way to hold a dream is to touch it.",
                teach: "When a dream feels unstable, engage your senses: rub your hands together, touch a surface, look closely at small details, even say \"increase clarity\" out loud. Filling your senses anchors you in the dream and pushes back the pull of waking.",
                quiz: LucidQuiz(
                    question: "What's a reliable stabilization move?",
                    options: [
                        "Closing your dream eyes tight",
                        "Rubbing your hands and engaging your senses",
                        "Standing perfectly still and waiting"
                    ],
                    answer: 1,
                    why: "Active sensory engagement anchors you firmly inside the dream."
                ),
                reflection: "Which sense do you notice most vividly in your dreams — sight, touch, sound?",
                challenge: "Practice rubbing your hands together now, and plan to do it the moment you go lucid.",
                done: "You've got an anchor for any wobbling dream. Touch it, and it holds.",
                tip: "Rubbing hands is the dreamer's classic for a reason — it works fast and anywhere.",
                didYouKnow: "Engaging dream touch and detail seems to recruit your sensory brain areas and pull attention into the dream — giving the fading scene something concrete to hold onto instead of slipping toward waking."
            ),
            LucidLessonContent(
                id: "stable-3",
                title: "The Spinning Technique",
                icon: "arrow.triangle.2.circlepath",
                hook: "When a dream starts to fade to black, you can spin it back to life.",
                teach: "If the dream dims, spin your dream body around like a top. The motion floods your senses and often prevents waking — sometimes dropping you into a fresh scene. As you slow down, expect a vivid dream, and reality-check to confirm you're still in.",
                quiz: LucidQuiz(
                    question: "What can spinning your dream body do?",
                    options: [
                        "Wake you instantly",
                        "Revive a fading dream, sometimes shifting the scene",
                        "Nothing — it's a myth"
                    ],
                    answer: 1,
                    why: "Spinning floods the senses and often saves a collapsing dream."
                ),
                reflection: "When something is slipping away, does motion or stillness usually refocus you?",
                challenge: "Memorize the move: if a dream fades, spin. Picture doing it before sleep tonight.",
                done: "You've got a rescue move. A fading dream no longer means game over.",
                tip: "Expect the dream to continue as you spin — your expectation shapes what you find.",
                didYouKnow: "Spinning is a long-standing dreamer's trick: the flood of motion gives your senses something vivid to process, often reviving a collapsing dream — and because the old scene dissolves, you sometimes land somewhere entirely new."
            ),
            LucidLessonContent(
                id: "stable-4",
                title: "Calm Is Control",
                icon: "leaf.arrow.triangle.circlepath",
                hook: "The most powerful tool in any lucid dream isn't a trick. It's your emotional state.",
                teach: "Dreams amplify emotion. Panic distorts them and wakes you; calm steadies and sustains them. Treat emotional steadiness as your core skill — slow your dream breathing, soften your reactions, and the dream becomes stable and responsive.",
                quiz: LucidQuiz(
                    question: "What's the deepest stabilization skill?",
                    options: [
                        "Moving as fast as you can",
                        "Staying emotionally calm and steady",
                        "Shouting commands at the dream"
                    ],
                    answer: 1,
                    why: "Dreams mirror your emotions — calm keeps them whole."
                ),
                reflection: "What calms you fastest in waking life? Could you bring it into a dream?",
                challenge: "Do one minute of slow breathing tonight as a rehearsal for staying calm in-dream.",
                done: "You've learned that calm is control. Steady the dreamer, and the dream steadies too.",
                tip: "If a dream turns intense, slow your breathing first — everything else follows.",
                didYouKnow: "Dreams amplify whatever you feel, so your emotional state is the single biggest lever you have over how a dream behaves — calm makes it steady and responsive, panic distorts it and pulls you awake."
            ),
            LucidLessonContent(
                id: "stable-5",
                title: "Extending Your Time",
                icon: "hourglass.bottomhalf.filled",
                hook: "With a few small rituals, seconds of lucidity can stretch into minutes.",
                teach: "Combine your tools: ground your senses, stay calm, spin if needed, and keep gently engaging the dream rather than just watching. Some dreamers even say \"the dream continues\" out loud to reinforce it. Each habit buys you more time inside.",
                quiz: LucidQuiz(
                    question: "How do you make lucid dreams last longer?",
                    options: [
                        "Stay passive and hope",
                        "Combine grounding, calm, and active engagement",
                        "Try to control everything at once"
                    ],
                    answer: 1,
                    why: "Layering your stabilization habits steadily extends your time in the dream."
                ),
                reflection: "Which stabilization tool feels most natural to you so far?",
                challenge: "Plan your in-dream sequence: realize → calm → rub hands → engage. Rehearse it tonight.",
                done: "Stabilization complete. You can not only enter the dream — you can stay and explore it.",
                tip: "Don't try to do everything. One calm, grounding habit, done well, is enough to hold a dream.",
                didYouKnow: "Early lucid dreams often last only seconds, but practitioners who layer these stabilization habits report stretching them into many minutes — and occasionally far longer — of clear, explorable dreaming."
            )
        ]
    )

    // MARK: - 8. Common Problems

    private static let commonProblems = LucidSectionContent(
        id: "problems",
        title: "Common Problems",
        subtitle: "Every dreamer hits these walls — here's how to walk through",
        icon: "lifepreserver.fill",
        lessons: [
            LucidLessonContent(
                id: "problems-1",
                title: "\"I Never Remember My Dreams\"",
                icon: "questionmark.square.dashed",
                hook: "The most common wall is also the most fixable. Recall can be rebuilt from zero.",
                teach: "If you remember nothing, return to basics: set the intention before sleep, stay still on waking, and write down anything — even \"blank.\" Within days or weeks, recall almost always returns. It's a muscle, and it responds to consistent, gentle use.",
                quiz: LucidQuiz(
                    question: "You remember no dreams at all. What's the move?",
                    options: [
                        "Give up — you're one of the people who can't",
                        "Rebuild recall: intention, stillness, and writing anything down",
                        "Sleep more hours every night"
                    ],
                    answer: 1,
                    why: "Recall is trainable for almost everyone — patience rebuilds it."
                ),
                reflection: "Which recall basic have you been skipping — intention, stillness, or writing?",
                challenge: "Tonight, set the intention and, on waking, write one line even if it's \"nothing yet.\"",
                done: "You've turned the most discouraging wall into a simple, solvable habit.",
                tip: "Don't measure one night. Measure the trend over two weeks — it climbs.",
                didYouKnow: "Even people convinced they \"never dream\" almost always start recalling dreams within a week or two of keeping a journal. They were dreaming all along — the memories simply weren't being caught."
            ),
            LucidLessonContent(
                id: "problems-2",
                title: "\"I Realize, Then Wake Up\"",
                icon: "bolt.slash.fill",
                hook: "So close: you knew you were dreaming — for about two seconds. Let's fix that.",
                teach: "Premature waking is almost always excitement plus lack of grounding. The instant you go lucid, calm yourself and immediately stabilize — rub your hands, touch something, look at detail. Don't celebrate; engage. The dream will hold.",
                quiz: LucidQuiz(
                    question: "You go lucid but wake instantly. The fix?",
                    options: [
                        "Celebrate loudly",
                        "Stay calm and stabilize right away",
                        "Try to fly immediately"
                    ],
                    answer: 1,
                    why: "Calm + immediate grounding is the cure for the wake-up rush."
                ),
                reflection: "What will be your very first action next time you realize you're dreaming?",
                challenge: "Rehearse the first move tonight: \"lucid → calm → rub hands.\"",
                done: "You've got a plan for the most heartbreaking near-miss in lucid dreaming.",
                tip: "Look at the ground or your hands — detail anchors you faster than anything.",
                didYouKnow: "Waking the instant you go lucid is the most common beginner complaint — and one of the most fixable, because it's about your state in that moment, not a lack of skill. The cure is calm, not more effort."
            ),
            LucidLessonContent(
                id: "problems-3",
                title: "\"Nothing's Working\"",
                icon: "tortoise.fill",
                hook: "Plateaus are normal. They're not failure — they're the part right before it clicks.",
                teach: "Progress in lucid dreaming is uneven, with dry spells that test your patience. Don't pile on pressure or technique-hop nightly. Keep a steady, gentle routine, protect your sleep, and trust the process. Breakthroughs often come after a calm stretch, not a frantic one.",
                quiz: LucidQuiz(
                    question: "You've had a long dry spell. What helps most?",
                    options: [
                        "Trying every technique at once, every night",
                        "A steady, gentle routine and patience",
                        "Quitting for good"
                    ],
                    answer: 1,
                    why: "Consistency through plateaus is what carries you to the breakthrough."
                ),
                reflection: "When you've learned hard skills before, how did you get past the plateau?",
                challenge: "Recommit to one simple routine for the next week — no chopping and changing.",
                done: "You've reframed the plateau: not a wall, but the runway before takeoff.",
                tip: "Lower the pressure. Lucidity comes more easily to a relaxed mind than a desperate one.",
                didYouKnow: "Plateaus show up in every kind of skill learning, from music to sports. Breakthroughs frequently arrive after a calm, consistent stretch rather than a frantic push — progress was building under the surface the whole time."
            ),
            LucidLessonContent(
                id: "problems-4",
                title: "When Control Won't Obey",
                icon: "slider.horizontal.3",
                hook: "You try to summon something and... nothing. Dream control has a strange secret.",
                teach: "Dreams respond to expectation, not force. Demanding something often makes it resist; calmly expecting it makes it appear. Use indirect tricks — look away and back, reach into a pocket, walk through a door — and trust it'll be there. Belief is the real control.",
                quiz: LucidQuiz(
                    question: "Why won't the dream do what you command?",
                    options: [
                        "Dreams respond to calm expectation, not force",
                        "You're not trying hard enough",
                        "Control is impossible"
                    ],
                    answer: 0,
                    why: "Expectation shapes dreams; forcing creates resistance."
                ),
                reflection: "Where in life does 'trying harder' backfire and 'expecting calmly' work better?",
                challenge: "Plan one indirect trick to try in-dream: reach into a pocket and expect what you want.",
                done: "You've learned the paradox of dream control: let go, and it answers.",
                tip: "Look away from what's failing, expect it behind you, then turn back. It's often there.",
                didYouKnow: "This mirrors how mental imagery works awake: the mind tends to resist forced commands but follows calm, confident expectation. In a dream, that quirk becomes your main tool for control."
            ),
            LucidLessonContent(
                id: "problems-5",
                title: "Nightmares & Fear",
                icon: "cloud.bolt.rain.fill",
                hook: "A frightening dream is one of the best chances to become lucid — and to take its power back.",
                teach: "Nightmares are vivid and emotional, which makes them easy to recognize as dreams. Once lucid, you don't have to fight or flee — you can calm yourself, turn and face what scares you, or simply change the scene. Approached gently, recurring nightmares often lose their grip.",
                quiz: LucidQuiz(
                    question: "If you become lucid in a nightmare, a healthy response is to…",
                    options: [
                        "Panic and try to wake instantly",
                        "Calm yourself and face or transform the dream",
                        "Never sleep again"
                    ],
                    answer: 1,
                    why: "Calmly facing a nightmare, once lucid, can drain its fear over time."
                ),
                reflection: "Is there a recurring fear in your dreams you'd meet differently if you knew it wasn't real?",
                challenge: "Decide your calm response in advance: \"It's a dream. I'm safe. I can face this.\"",
                done: "You've turned your scariest dreams into doorways — and into practice.",
                tip: "If a dream is ever too much, you can always choose to wake. You're always in charge.",
                didYouKnow: "Lucidity is being studied as a genuine therapy for chronic nightmares: a technique called imagery rehearsal helps people calmly re-script recurring bad dreams, and lucid awareness can make that shift happen from inside the dream itself."
            ),
            LucidLessonContent(
                id: "problems-6",
                title: "Sleep First",
                icon: "bed.double.circle.fill",
                hook: "The wisest dreamers know exactly when to stop trying. Rest is part of the craft.",
                teach: "If you're exhausted, stressed, or sleep-deprived, set the techniques aside and just sleep. Lucid dreaming should enrich your life, never cost you your health. Well-rested minds dream more vividly and recall more anyway — so rest isn't a break from practice, it is practice.",
                quiz: LucidQuiz(
                    question: "When should you skip lucid practice?",
                    options: [
                        "Never — push through always",
                        "When you're exhausted or run-down; rest comes first",
                        "Only on holidays"
                    ],
                    answer: 1,
                    why: "Health and sleep always come first — and they make you a better dreamer."
                ),
                reflection: "How do you tell the difference between a tired night to push and one to simply rest?",
                challenge: "Tonight, honestly check in: if you're drained, skip the techniques and sleep deeply.",
                done: "Common Problems complete. You can navigate the walls — and know when to simply rest.",
                tip: "A rested dreamer beats a burnt-out one every time. Sleep is never wasted.",
                didYouKnow: "Sleep deprivation measurably cuts both REM time and dream recall — the two things lucid dreaming needs most. Resting fully isn't stepping away from the practice; it's quietly strengthening it."
            )
        ]
    )

    // MARK: - 9. Advanced Practice

    private static let advanced = LucidSectionContent(
        id: "advanced",
        title: "Advanced Practice",
        subtitle: "You've crossed the threshold — now learn what's possible",
        icon: "star.circle.fill",
        lessons: [
            LucidLessonContent(
                id: "advanced-1",
                title: "Summoning & Changing Scenes",
                icon: "wand.and.stars",
                hook: "Want to be somewhere else? In a dream, the doorway is wherever you decide it is.",
                teach: "To change scenes, use a portal you believe in: walk through a door, close your eyes and expect a new place, or spin and picture your destination. To summon objects, reach somewhere you can't see — a pocket, behind your back — and expect it there. Expectation does the work.",
                quiz: LucidQuiz(
                    question: "What's a reliable way to change a dream scene?",
                    options: [
                        "Forcing the walls to dissolve",
                        "Walking through a door while expecting your destination",
                        "Waiting for it to change on its own"
                    ],
                    answer: 1,
                    why: "A believed-in portal plus expectation reshapes the dream smoothly."
                ),
                reflection: "If you could open a door to anywhere tonight, where would it lead?",
                challenge: "Choose your go-to portal (a door, a fog, a spin) and your first destination.",
                done: "You've learned to bend the dream's geography. The whole dreamscape is yours to travel.",
                tip: "Commit fully to the method you pick. Half-belief gives you half a door.",
                didYouKnow: "Scene changes work because the dreaming brain rebuilds your surroundings on the fly from expectation rather than from a fixed map — which is why walking through a door and expecting somewhere new actually delivers it."
            ),
            LucidLessonContent(
                id: "advanced-2",
                title: "Talking to Dream Characters",
                icon: "bubble.left.and.bubble.right.fill",
                hook: "Ask a dream character a question and the answer can genuinely surprise you.",
                teach: "Dream characters are generated by your own mind, yet they can act with startling independence. Talking to them — asking who they are, or what they represent — can be moving, strange, even insightful. Approach with curiosity and respect, as you would a real conversation.",
                quiz: LucidQuiz(
                    question: "Dream characters are best understood as…",
                    options: [
                        "Real external beings",
                        "Creations of your own mind that can still surprise you",
                        "Always meaningless background"
                    ],
                    answer: 1,
                    why: "They come from you, yet can behave with surprising autonomy and insight."
                ),
                reflection: "If you could ask a dream character one question, what would it be?",
                challenge: "Decide your one question now, ready for your next lucid encounter.",
                done: "You've opened a dialogue with your own depths. Some answers stay with you for years.",
                tip: "Be kind to dream characters. How you treat them often shapes how the dream responds.",
                didYouKnow: "Researchers have actually run experiments with lucid dreamers asking their dream characters to do math or make rhymes — the answers are often \"wrong\" or surprising, offering a strange window into how the dreaming mind builds these figures from within."
            ),
            LucidLessonContent(
                id: "advanced-3",
                title: "Flight & Movement",
                icon: "bird.fill",
                hook: "Flying is the dream everyone wants. The only thing holding you down is doubt.",
                teach: "Flight in dreams runs on belief, not technique. Pick a method you trust — leap and soar, swim through the air, imagine a pull from above — and commit to it without hesitation. Doubt is gravity here. Expect to fly, and you will.",
                quiz: LucidQuiz(
                    question: "What's the real key to flying in a dream?",
                    options: [
                        "The perfect arm motion",
                        "Unshakable belief and expectation",
                        "Finding a tall enough cliff"
                    ],
                    answer: 1,
                    why: "Belief is the engine of dream flight — doubt is the only thing that grounds you."
                ),
                reflection: "What kind of flying calls to you — soaring, floating, rocketing upward?",
                challenge: "Pick your flight method and rehearse the feeling of total confidence in it.",
                done: "You've claimed the sky. Movement in dreams now bends to your belief.",
                tip: "If you stall mid-air, don't panic — look up, expect to rise, and you'll lift again.",
                didYouKnow: "Flying is one of the most universally reported pleasant dreams across cultures and eras — a near-universal human experience, and for many people the very first thing they try once they realize they're dreaming."
            ),
            LucidLessonContent(
                id: "advanced-4",
                title: "Setting Dream Goals",
                icon: "target",
                hook: "Lucid time is precious. Decide what to do with it before you arrive.",
                teach: "Many dreamers waste their first lucid moments unsure what to do. Choose a single, clear goal in advance — a place to visit, a person to meet, a thing to try. Holding one intention focuses the dream and makes the experience richer and more memorable.",
                quiz: LucidQuiz(
                    question: "Why set a dream goal beforehand?",
                    options: [
                        "It guarantees a lucid dream",
                        "Lucid time is short — a clear goal focuses and enriches it",
                        "Goals don't matter in dreams"
                    ],
                    answer: 1,
                    why: "A pre-set intention keeps you from wasting precious, fleeting lucid time."
                ),
                reflection: "If you became lucid tonight, what's the one thing you'd most want to do?",
                challenge: "Write down a single dream goal and hold it as you fall asleep.",
                done: "You've given your lucidity a purpose. Every dream now has a destination.",
                tip: "Keep one goal at a time. A focused dreamer goes deeper than a scattered one.",
                didYouKnow: "Setting one clear goal beforehand is among the most reliable ways experienced dreamers make the most of a short lucid window — and it doubles as a MILD-style intention that can help trigger lucidity in the first place."
            ),
            LucidLessonContent(
                id: "advanced-5",
                title: "Deepening & Super-Vividness",
                icon: "eye.circle.fill",
                hook: "Some lucid dreams feel more real than waking life. That clarity can be deliberately summoned.",
                teach: "To deepen a dream, engage it fully: examine textures up close, listen, taste, and say \"clarity now\" if it helps. The more sensory attention you pour in, the more vivid and stable the world becomes — sometimes startlingly hyper-real.",
                quiz: LucidQuiz(
                    question: "How do you make a dream more vivid?",
                    options: [
                        "Squint and concentrate hard",
                        "Pour rich sensory attention into the details around you",
                        "Try to ignore the dream"
                    ],
                    answer: 1,
                    why: "Deep sensory engagement sharpens and stabilizes the dream world."
                ),
                reflection: "What detail would you study first if a dream became more real than waking?",
                challenge: "Plan to examine one small object in close, sensory detail next time you're lucid.",
                done: "You've learned to turn up the dream's resolution. Reality has competition now.",
                tip: "Looking closely at your dream hands is a classic way to instantly deepen a scene.",
                didYouKnow: "Some lucid dreams are reported as feeling \"more real than waking life\" — vividness you can deliberately turn up. The more sensory attention you pour into the details around you, the sharper and more stable the dream world becomes."
            ),
            LucidLessonContent(
                id: "advanced-6",
                title: "Your Dreaming Practice",
                icon: "infinity.circle.fill",
                hook: "You've learned the whole path. Now the real journey — a lifelong one — begins.",
                teach: "Lucid dreaming isn't a level you beat; it's a practice you keep. Hold onto the habits that work for you, stay curious, protect your sleep, and let your dream life grow alongside your waking one. You're not finished — you're a dreamer now, and the night is yours.",
                quiz: LucidQuiz(
                    question: "What's the best way to think about lucid dreaming long-term?",
                    options: [
                        "A one-time achievement to unlock and forget",
                        "A lifelong practice you keep gently tending",
                        "Something only beginners work at"
                    ],
                    answer: 1,
                    why: "It's a practice, not a finish line — it deepens for as long as you tend it."
                ),
                reflection: "What kind of dreamer do you want to be a year from now?",
                challenge: "Choose the one habit from this whole path you'll keep forever — and start tonight.",
                done: "You've completed the path. From the half-light of curiosity to a true dreamer — the night is yours now.",
                tip: "Revisit any lesson anytime. Even masters return to the foundations.",
                didYouKnow: "Long-term practitioners often describe lucid dreaming the way meditators describe their practice: not a skill you finish, but one that keeps unfolding and deepening for years as you keep gently tending it."
            )
        ]
    )
}
