import '../models/models.dart';

class DemoData {
  static List<UserProfile> sampleDeck() {
    return [
      UserProfile(
        id: 'demo-1',
        name: 'Aisha',
        age: 24,
        gender: 'Woman',
        photos: [
          'https://images.unsplash.com/photo-1534597466652-a5a2a8a9a8b6?auto=format&fit=crop&w=800&q=80',
        ],
        city: 'Pune',
        distanceKm: 3,
        bio: 'UI designer by day, indie music photographer by weekend.',
        occupation: 'Product Designer',
        education: 'Art College',
        relationshipIntent: 'Dating & Weekend Plans',
        interests: const [
          'Indie Music',
          'Photography',
          'Plant Parenting',
          'Matcha',
        ],
        isPhotoVerified: true,
        trustScore: 88,
        crossedPathsCount: 3,
        compatibilityExplanation:
            '3 km away • verified • shared: Indie Music, Matcha',
      ),
      UserProfile(
        id: 'demo-2',
        name: 'Rohan',
        age: 28,
        gender: 'Man',
        photos: [
          'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?auto=format&fit=crop&w=800&q=80',
        ],
        city: 'Pune',
        distanceKm: 7,
        bio: 'Weekend cyclist, F1 nerd, and amateur mixologist.',
        occupation: 'DevOps Engineer',
        education: 'Engineering College',
        relationshipIntent: 'Dating',
        interests: const ['Cycling', 'F1', 'Coffee Roasting', 'Jazz'],
        isPhotoVerified: true,
        trustScore: 75,
        crossedPathsCount: 5,
        compatibilityExplanation:
            '7 km away • verified • shared: Cycling, Coffee',
      ),
      UserProfile(
        id: 'demo-3',
        name: 'Meera',
        age: 25,
        gender: 'Woman',
        photos: [
          'https://images.unsplash.com/photo-1580489941917-2c6c489a2b6b?auto=format&fit=crop&w=800&q=80',
        ],
        city: 'Pune',
        distanceKm: 12,
        bio: 'Sourdough baker, bookstore hopper, and weekend market explorer.',
        occupation: 'Freelance Writer',
        education: 'Liberal Arts',
        relationshipIntent: 'Dating & Weekend Plans',
        interests: const ['Baking', 'Books', 'Hiking', 'Vintage Shopping'],
        isPhotoVerified: false,
        trustScore: 62,
        crossedPathsCount: 2,
        compatibilityExplanation: '12 km away • shared: Hiking',
      ),
    ];
  }

  static List<MatchItem> sampleMatches(UserProfile currentUser) {
    return [
      MatchItem(
        id: 'match-1',
        user: UserProfile(
          id: 'demo-match-1',
          name: 'Ishita',
          age: 23,
          gender: 'Woman',
          photos: [
            'https://images.unsplash.com/photo-1531123456789-abc123?auto=format&fit=crop&w=800&q=80',
          ],
          city: 'Pune',
          distanceKm: 4,
          bio: 'Art curator who loves weekend gallery hops.',
          occupation: 'Curator',
          isPhotoVerified: true,
          trustScore: 91,
          commonInterests: const ['Indie Music', 'Art'],
        ),
        matchedAt: DateTime.now()
            .subtract(const Duration(days: 1))
            .millisecondsSinceEpoch,
        lastMessage: 'That new exhibition at Jehangir looks amazing!',
        lastMessageTime: '2h ago',
        unreadCount: 2,
        suggestedStarter: 'What\'s the best weekend art market in Pune?',
      ),
      MatchItem(
        id: 'match-2',
        user: UserProfile(
          id: 'demo-match-2',
          name: 'Arjun',
          age: 27,
          gender: 'Man',
          photos: [
            'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?auto=format&fit=crop&w=800&q=80',
          ],
          city: 'Pune',
          distanceKm: 9,
          bio: 'Chef who experiments with fusion recipes on Sundays.',
          occupation: 'Chef',
          isPhotoVerified: true,
          trustScore: 85,
          commonInterests: const ['Coffee', 'Jazz'],
        ),
        matchedAt: DateTime.now()
            .subtract(const Duration(days: 3))
            .millisecondsSinceEpoch,
        lastMessage: 'I tried your pancake recipe — turned out great!',
        lastMessageTime: '1d ago',
        unreadCount: 0,
        suggestedStarter: 'Any recommendations for Sunday brunch spots?',
      ),
    ];
  }

  static Map<String, List<ChatMessage>> sampleMessages() {
    final now = DateTime.now();
    return {
      'match-1': [
        ChatMessage(
          id: 'msg-1',
          senderId: 'demo-match-1',
          text: 'Hey Max! I saw your profile — you also love Coldplay :)',
          timestamp: now
              .subtract(const Duration(hours: 2))
              .millisecondsSinceEpoch,
        ),
        ChatMessage(
          id: 'msg-2',
          senderId: 'demo-user',
          text: 'Yes! Saw them live in Mumbai last year. Amazing show.',
          timestamp: now
              .subtract(const Duration(hours: 1))
              .millisecondsSinceEpoch,
        ),
        ChatMessage(
          id: 'msg-3',
          senderId: 'demo-match-1',
          text: 'That new exhibition at Jehangir looks amazing!',
          timestamp: now
              .subtract(const Duration(hours: 1))
              .millisecondsSinceEpoch,
        ),
      ],
    };
  }

  static List<WeekendPlan> samplePlans() {
    return [
      WeekendPlan(
        id: 'plan-1',
        creatorId: 'demo-user',
        creatorName: 'Max',
        creatorPhoto:
            'https://images.unsplash.com/photo-1539571696357-5a69c17a67c6?auto=format&fit=crop&w=800&q=80',
        title: 'Sunday Brunch Crawl',
        category: 'Food',
        venue: 'Multiple cafes in Koregaon Park',
        time: 'Sun, Sep 14 · 10:30 AM',
        description:
            'Visiting 3 cafe stops for brunch — coffee, pancakes, and pastries!',
        participants: const ['Max', 'Aisha'],
        isJoined: true,
      ),
      WeekendPlan(
        id: 'plan-2',
        creatorId: 'demo-2',
        creatorName: 'Rohan',
        creatorPhoto:
            'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?auto=format&fit=crop&w=800&q=80',
        title: 'Monsoon Trek to Sinhagad',
        category: 'Adventure',
        venue: 'Sinhagad Fort',
        time: 'Sat, Sep 20 · 7:00 AM',
        description:
            'Early morning trek with waterfall views. Bring water and snacks.',
        participants: const ['Max'],
        isJoined: false,
      ),
    ];
  }

  static List<CrossedPath> sampleCrossedPaths() {
    return [
      CrossedPath(
        userBId: 'demo-1',
        crossCount: 4,
        lastCrossedAt: DateTime.now().subtract(const Duration(days: 2)),
        userProfile: UserProfile(
          id: 'demo-1',
          name: 'Aisha',
          age: 24,
          gender: 'Woman',
          photos: [
            'https://images.unsplash.com/photo-1534597466652-a5a2a8a9a8b6?auto=format&fit=crop&w=800&q=80',
          ],
          city: 'Pune',
          distanceKm: 3,
          bio: 'UI designer by day, indie music photographer by weekend.',
          interests: const ['Indie Music', 'Photography', 'Plant Parenting'],
          commonInterests: const ['Indie Music'],
        ),
      ),
      CrossedPath(
        userBId: 'demo-3',
        crossCount: 2,
        lastCrossedAt: DateTime.now().subtract(const Duration(days: 5)),
        userProfile: UserProfile(
          id: 'demo-3',
          name: 'Meera',
          age: 25,
          gender: 'Woman',
          photos: [
            'https://images.unsplash.com/photo-1580489941917-2c6c489a2b6b?auto=format&fit=crop&w=800&q=80',
          ],
          city: 'Pune',
          distanceKm: 12,
          bio: 'Sourdough baker, bookstore hopper.',
          interests: const ['Baking', 'Books', 'Hiking'],
          commonInterests: const ['Hiking'],
        ),
      ),
    ];
  }
}
