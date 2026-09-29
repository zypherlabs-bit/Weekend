/// Weekend's own profile schema: the prompts a user answers, the lifestyle
/// attributes they pick, and the interests they select.
///
/// Design rules:
/// * Every string here is Weekend's own wording. The categories were chosen
///   to match what mature dating apps ask for - the FUNCTION is the
///   reference, not the text. No third-party prompt, brand or asset is
///   reproduced.
/// * Everything is a compile-time constant, so the picker, the validator and
///   the profile card all read from ONE source and cannot drift apart.
/// * Values match the CHECK constraints on the live `profiles` table, so a
///   value picked here can never be rejected by the database for being
///   outside the allowed set.

library;


class ProfilePromptTemplate {
  /// Stable identifier persisted alongside the answer. The human-readable
  /// [question] may be reworded later without invalidating saved answers.
  final String id;

  /// The question shown to the user.
  final String question;

  /// Short helper text under the question.
  final String hint;

  /// Maximum answer length, enforced by the client and by the
  /// `profile_prompts_shape` CHECK constraint on the server.
  final int maxLength;

  const ProfilePromptTemplate({
    required this.id,
    required this.question,
    required this.hint,
    this.maxLength = 300,
  });
}

/// A group of prompts shown as one section in Edit Profile.
class PromptSection {
  final String title;
  final String subtitle;
  final List<ProfilePromptTemplate> prompts;

  const PromptSection({
    required this.title,
    required this.subtitle,
    required this.prompts,
  });
}

/// One selectable lifestyle attribute (smoking / drinking / ...).
class LifestyleOption {
  final String value;
  final String label;
  const LifestyleOption(this.value, this.label);
}

/// A labelled group of lifestyle options, backed by one `profiles` column.
class LifestyleField {
  /// The `profiles` column this field writes to.
  final String column;

  final String label;
  final String question;
  final List<LifestyleOption> options;

  const LifestyleField({
    required this.column,
    required this.label,
    required this.question,
    required this.options,
  });
}

/// Catalogue of everything a Weekend profile can contain.
class ProfileSchema {
  ProfileSchema._();

  /// Minimum photos before a profile counts as complete.
  ///
  /// Mirrors `profile_requirements.min_photos` in the database (migration 025).
  /// The server is the authority; this is the value the UI uses to disable
  /// "Save" early and to explain what is missing.
  static const int minimumPhotos = 4;

  /// Maximum photos a profile may carry.
  static const int maximumPhotos = 6;

  /// Maximum number of prompts a profile may answer.
  static const int maxPrompts = 4;

  static const List<String> genders = [
    'Man',
    'Woman',
    'Non-binary',
    'Prefer not to say',
  ];

  static const List<String> relationshipIntents = [
    'Dating',
    'Long-term relationship',
    'New people & Friendships',
    'Dating & Weekend Plans',
  ];

  /// Prompt catalogue, grouped the way a mature dating app groups them.
  static const List<PromptSection> promptSections = [
    PromptSection(
      title: 'About me',
      subtitle: 'Answer as many as you like - we will show up to four.',
      prompts: [
        ProfilePromptTemplate(
          id: 'simple_pleasures',
          question: 'My simple pleasures',
          hint: 'The small things that reliably make your day better.',
        ),
        ProfilePromptTemplate(
          id: 'perfect_weekend',
          question: 'A perfect weekend looks like',
          hint: 'Saturday morning through Sunday night, in your words.',
        ),
        ProfilePromptTemplate(
          id: 'two_truths_and_a_lie',
          question: 'Two truths and a lie',
          hint: 'Give three statements. We will never say which one is the lie.',
        ),
        ProfilePromptTemplate(
          id: 'passionate_about',
          question: 'Something I am genuinely passionate about',
          hint: 'The thing you would talk about unprompted.',
        ),
        ProfilePromptTemplate(
          id: 'typical_sunday',
          question: 'My typical Sunday',
          hint: 'The real one, not the aspirational one.',
        ),
        ProfilePromptTemplate(
          id: 'ideal_first_date',
          question: 'My ideal first date',
          hint: 'Where, how long, and what we would talk about.',
        ),
        ProfilePromptTemplate(
          id: 'random_fact',
          question: 'A random fact about me',
          hint: 'Something true that does not fit anywhere else.',
        ),
        ProfilePromptTemplate(
          id: 'win_me_over',
          question: 'The way to win me over',
          hint: 'Be specific. Generic answers help nobody.',
        ),
        ProfilePromptTemplate(
          id: 'hidden_talent',
          question: 'My hidden talent',
          hint: 'You would be surprised if you saw it.',
        ),
        ProfilePromptTemplate(
          id: 'want_to_try',
          question: 'Something I want to try',
          hint: 'New, slightly out of your comfort zone.',
        ),
      ],
    ),
    PromptSection(
      title: 'How I show up',
      subtitle: 'Lifestyle answers that set expectations honestly.',
      prompts: [
        ProfilePromptTemplate(
          id: 'weekend_ritual',
          question: 'My weekend ritual',
          hint: 'The thing you do every weekend without fail.',
        ),
        ProfilePromptTemplate(
          id: 'friendship_style',
          question: 'My friendship style',
          hint: 'How you keep in touch, and how often.',
        ),
        ProfilePromptTemplate(
          id: 'messiest_or_cleanest',
          question: 'Neat, tidy or creative chaos?',
          hint: 'One honest word is plenty.',
        ),
        ProfilePromptTemplate(
          id: 'always_will',
          question: 'Something I will always do',
          hint: 'A principle you actually hold to.',
        ),
        ProfilePromptTemplate(
          id: 'currently_into',
          question: 'What I am into right now',
          hint: 'Not a life goal - what has your attention this month.',
        ),
      ],
    ),
  ];

  /// Every prompt id, for validating a saved answer set.
  static List<String> get allPromptIds => [
    for (final section in promptSections)
      for (final p in section.prompts) p.id,
  ];

  static ProfilePromptTemplate? promptById(String id) {
    for (final section in promptSections) {
      for (final p in section.prompts) {
        if (p.id == id) return p;
      }
    }
    return null;
  }

  /// The question text for a saved answer, or the stored text when the id is
  /// from an older catalogue version. Never returns an empty string.
  static String promptQuestion(String id, String fallback) {
    final template = promptById(id);
    if (template != null) return template.question;
    return fallback.trim().isEmpty ? 'A little about me' : fallback;
  }

  /// Lifestyle attributes.
  ///
  /// Each `LifestyleField.options` list is EXACTLY the set its column's CHECK
  /// constraint accepts (migration 023, live). Keeping them identical is what
  /// guarantees the app can never submit a value the database would reject.
  static const LifestyleField smoking = LifestyleField(
    column: 'smoking',
    label: 'Smoking',
    question: 'How often do you smoke?',
    options: [
      LifestyleOption('Never', 'Never'),
      LifestyleOption('Occasionally', 'Occasionally'),
      LifestyleOption('Often', 'Often'),
      LifestyleOption('Prefer not to say', 'Prefer not to say'),
    ],
  );

  static const LifestyleField drinking = LifestyleField(
    column: 'drinking',
    label: 'Drinking',
    question: 'How often do you drink?',
    options: [
      LifestyleOption('Never', 'Never'),
      LifestyleOption('Socially', 'Socially'),
      LifestyleOption('Often', 'Often'),
      LifestyleOption('Prefer not to say', 'Prefer not to say'),
    ],
  );

  static const LifestyleField exercise = LifestyleField(
    column: 'exercise',
    label: 'Exercise',
    question: 'How often do you exercise?',
    options: [
      LifestyleOption('Rarely', 'Rarely'),
      LifestyleOption('Sometimes', 'Sometimes'),
      LifestyleOption('Regularly', 'Regularly'),
      LifestyleOption('Prefer not to say', 'Prefer not to say'),
    ],
  );

  static const LifestyleField pets = LifestyleField(
    column: 'pets',
    label: 'Pets',
    question: 'Do you have pets?',
    options: [
      LifestyleOption('None', 'None'),
      LifestyleOption('Dog', 'Dog'),
      LifestyleOption('Cat', 'Cat'),
      LifestyleOption('Both', 'Both'),
      LifestyleOption('Other', 'Other'),
      LifestyleOption('Prefer not to say', 'Prefer not to say'),
    ],
  );

  static const LifestyleField children = LifestyleField(
    column: 'children',
    label: 'Children',
    question: 'Do you want children?',
    options: [
      LifestyleOption('No', 'No'),
      LifestyleOption('Want later', 'Want later'),
      LifestyleOption('Have', 'Have'),
      LifestyleOption('Prefer not to say', 'Prefer not to say'),
    ],
  );

  static const List<LifestyleField> lifestyleFields = [
    smoking,
    drinking,
    exercise,
    pets,
    children,
  ];

  /// Languages offered in the picker.
  ///
  /// Free text is also accepted; this list only drives the suggestions, so a
  /// language outside it is still valid.
  static const List<String> suggestedLanguages = [
    'English',
    'Hindi',
    'Marathi',
    'Bengali',
    'Telugu',
    'Tamil',
    'Kannada',
    'Malayalam',
    'Gujarati',
    'Punjabi',
    'Urdu',
    'Spanish',
    'French',
    'German',
    'Japanese',
    'Portuguese',
    'Mandarin',
  ];

  /// Interest catalogue with display groups.
  ///
  /// Backed by the normalised `interests` table seeded in migration 025, so a
  /// chip here always maps onto a real row. The category is duplicated here
  /// only to group the picker without a round trip; the database remains the
  /// authority for what actually exists.
  static const Map<String, List<String>> interestCategories = {
    'Outdoors': [
      'Travel',
      'Camping',
      'Hiking',
      'Nature walks',
      'Beach days',
      'Road trips',
    ],
    'Culture': [
      'Movies',
      'Live music',
      'Stand-up comedy',
      'Theatre',
      'Art galleries',
      'Museums',
      'Bookshops',
      'Reading',
      'Board games',
      'Music festivals',
    ],
    'Food & drink': [
      'Cooking',
      'Baking',
      'Street food',
      'Coffee',
      'Wine',
      'Craft beer',
      'Restaurants',
    ],
    'Active': [
      'Fitness',
      'Cycling',
      'Running',
      'Yoga',
      'Swimming',
      'Team sports',
      'Climbing',
      'Football',
      'Cricket',
    ],
    'Screen': ['Gaming', 'Streaming', 'Podcasts'],
    'Creative': [
      'Photography',
      'Design',
      'Writing',
      'Making',
      'Gardening',
      'Technology',
      'Startups',
    ],
    'Community': [
      'Volunteering',
      'Weekend markets',
      'Live sport',
      'Volunteer runs',
      'Local festivals',
    ],
  };

  /// Every interest, flattened, de-duplicated, in catalogue order.
  static List<String> get allInterests {
    final out = <String>[];
    for (final group in interestCategories.values) {
      for (final name in group) {
        if (!out.contains(name)) out.add(name);
      }
    }
    return out;
  }

  /// Whether a value is acceptable for a `profiles` CHECK-constrained column.
  static bool isValidLifestyleValue(String column, String? value) {
    if (value == null) return true; // NULL is always allowed
    for (final field in lifestyleFields) {
      if (field.column != column) continue;
      return field.options.any((o) => o.value == value);
    }
    return false;
  }

  /// Whether a gender value is acceptable.
  static bool isValidGender(String value) => genders.contains(value);

  /// Whether a relationship-intent value is acceptable.
  static bool isValidRelationshipIntent(String value) =>
      relationshipIntents.contains(value);
}
