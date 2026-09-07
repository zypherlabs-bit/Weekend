package com.example.data.mock

import com.example.data.model.DateIdea
import com.example.data.model.ProfilePrompt
import com.example.data.model.UserProfile
import com.example.data.model.WeekendPlan

object SampleData {

    val initialProfiles = listOf(
        UserProfile(
            id = "user_1",
            name = "Aanya",
            age = 24,
            gender = "Woman",
            photos = listOf(
                "https://images.unsplash.com/photo-1534528741775-53994a69daeb?auto=format&fit=crop&w=800&q=80",
                "https://images.unsplash.com/photo-1517841905240-472988babdf9?auto=format&fit=crop&w=800&q=80",
                "https://images.unsplash.com/photo-1524504388940-b1c1722653e1?auto=format&fit=crop&w=800&q=80"
            ),
            city = "Pune",
            distanceKm = 2,
            bio = "Product designer by day, indie gig chaser by dusk. Always down for flat whites & spontaneous sunset drives up Sinhagad.",
            occupation = "UI/UX Designer",
            education = "Symbiosis Institute",
            relationshipIntent = "Long-term relationship",
            interests = listOf("Specialty Coffee", "Hiking", "Indie Music", "Photography", "F1", "Art Galleries"),
            favoritePlaces = listOf("Blue Tokai Cafe", "Viman Nagar Social", "ARAI Hills"),
            languages = listOf("English", "Hindi", "Marathi"),
            prompts = listOf(
                ProfilePrompt("“Good coffee, better conversations ☕”", "Morning pour-over, browsing an independent bookstore, then rooftop tapas with live acoustic jazz."),
                ProfilePrompt("My ideal weekend is...", "Sunset trek, craft coffee tasting, and live acoustic music."),
                ProfilePrompt("Let's go...", "To that hidden heritage bakery in Camp for warm sourdough!")
            ),
            isPhotoVerified = true,
            trustScore = 98,
            crossedPathsCount = 3,
            favoriteMusic = "Prateek Kuhad, Cigarettes After Sex, Tame Impala",
            idealWeekend = "Coffee tasting + hill climb"
        ),
        UserProfile(
            id = "user_2",
            name = "Rohan",
            age = 27,
            gender = "Man",
            photos = listOf(
                "https://images.unsplash.com/photo-1506794778202-cad84cf45f1d?auto=format&fit=crop&w=800&q=80",
                "https://images.unsplash.com/photo-1500648767791-00dcc994a43e?auto=format&fit=crop&w=800&q=80"
            ),
            city = "Pune",
            distanceKm = 4,
            bio = "Architect & cycling enthusiast. Can build a house from scratch and cook a killer cacio e pepe. Looking for someone genuine to explore secret spots.",
            occupation = "Senior Architect",
            education = "COEP Pune",
            relationshipIntent = "Dating",
            interests = listOf("Cycling", "Architecture", "Italian Cooking", "Bouldering", "Vinyl Records"),
            favoritePlaces = listOf("Third Wave Coffee", "Koregaon Park Lane 7", "Pashan Lake"),
            languages = listOf("English", "Hindi"),
            prompts = listOf(
                ProfilePrompt("My perfect Sunday...", "Early 40km sunrise ride towards Khadakwasla, then making fresh pasta from scratch."),
                ProfilePrompt("The fastest way to impress me is...", "Knowing where to get authentic filter coffee at 6 AM.")
            ),
            isPhotoVerified = true,
            trustScore = 99,
            crossedPathsCount = 5,
            favoriteMusic = "Dire Straits, Khruangbin, Daft Punk",
            idealWeekend = "Early cycling trail + brunch"
        ),
        UserProfile(
            id = "user_3",
            name = "Meera",
            age = 25,
            gender = "Woman",
            photos = listOf(
                "https://images.unsplash.com/photo-1529626455594-4ff0802cfb7e?auto=format&fit=crop&w=800&q=80",
                "https://images.unsplash.com/photo-1494790108377-be9c29b29330?auto=format&fit=crop&w=800&q=80"
            ),
            city = "Mumbai",
            distanceKm = 12,
            bio = "Documentary filmmaker & pottery dabbler. Obsessed with street photography and good storytelling. Visiting Pune often for shoots!",
            occupation = "Documentary Filmmaker",
            education = "FTII Alumni",
            relationshipIntent = "Casual dating",
            interests = listOf("Cinema", "Pottery", "Street Food", "Film Photography", "Bookstores", "Travel"),
            favoritePlaces = listOf("Kala Ghoda Cafe", "Prithvi Theatre", "German Bakery"),
            languages = listOf("English", "Hindi", "French"),
            prompts = listOf(
                ProfilePrompt("Let's go...", "To a midnight photography walk and hunt down the best butter pav bhaji."),
                ProfilePrompt("One thing I could talk about for hours...", "Old French new wave cinema and analog film cameras.")
            ),
            isPhotoVerified = true,
            trustScore = 97,
            crossedPathsCount = 2,
            favoriteMusic = "Norah Jones, Anoushka Shankar, Leon Bridges",
            idealWeekend = "Art cinema screening + street food crawl"
        ),
        UserProfile(
            id = "user_4",
            name = "Kabir",
            age = 28,
            gender = "Man",
            photos = listOf(
                "https://images.unsplash.com/photo-1519085360753-af0119f7cbe7?auto=format&fit=crop&w=800&q=80",
                "https://images.unsplash.com/photo-1492562080023-ab3db95bfbce?auto=format&fit=crop&w=800&q=80"
            ),
            city = "Pune",
            distanceKm = 6,
            bio = "Fintech founder, amateur guitarist, and avid mountaineer. Planning a trek to the Valley of Flowers this monsoon.",
            occupation = "Co-founder at PayFlow",
            education = "IIT Bombay",
            relationshipIntent = "Long-term relationship",
            interests = listOf("Trekking", "Guitar", "Startups", "Board Games", "Running", "Dogs"),
            favoritePlaces = listOf("High Spirits Cafe", "FC Road Social", "Empress Botanical Garden"),
            languages = listOf("English", "Hindi", "Punjabi"),
            prompts = listOf(
                ProfilePrompt("My ideal weekend is...", "Campfire acoustic jam under a star-filled sky, or a competitive Catan marathon."),
                ProfilePrompt("The fastest way to impress me is...", "Bringing your dog along to our first meetup!")
            ),
            isPhotoVerified = true,
            trustScore = 95,
            crossedPathsCount = 1,
            favoriteMusic = "Coldplay, The Local Train, Oasis",
            idealWeekend = "Trekking & acoustic jam"
        ),
        UserProfile(
            id = "user_5",
            name = "Elena",
            age = 26,
            gender = "Woman",
            photos = listOf(
                "https://images.unsplash.com/photo-1544005313-94ddf0286df2?auto=format&fit=crop&w=800&q=80",
                "https://images.unsplash.com/photo-1517841905240-472988babdf9?auto=format&fit=crop&w=800&q=80"
            ),
            city = "Barcelona / Remote in Pune",
            distanceKm = 8,
            bio = "Digital nomad & yoga instructor originally from Spain, spending the season here. Looking for locals to exchange culture and explore hidden waterfalls.",
            occupation = "Yoga Teacher & Travel Writer",
            education = "University of Barcelona",
            relationshipIntent = "New people & Friendships",
            interests = listOf("Yoga", "Travel", "Languages", "Vegetarian Food", "Hiking", "Live Music"),
            favoritePlaces = listOf("Osho Teerth Park", "Zen Cafe", "Mulshi Lake"),
            languages = listOf("Spanish", "English", "Catalan", "Learning Hindi"),
            prompts = listOf(
                ProfilePrompt("Let's go...", "Find a scenic cliff edge for sunset meditation, followed by spicy street masala chai."),
                ProfilePrompt("My ideal weekend is...", "Renting a scooter, getting slightly lost, and discovering an untouched waterfall.")
            ),
            isPhotoVerified = true,
            trustScore = 99,
            crossedPathsCount = 4,
            favoriteMusic = "Rosalía, Buena Vista Social Club, Tycho",
            idealWeekend = "Nature retreat + language exchange"
        )
    )

    val samplePlans = listOf(
        WeekendPlan(
            id = "plan_1",
            creatorId = "user_1",
            creatorName = "Ananya",
            creatorPhoto = "https://images.unsplash.com/photo-1534528741775-53994a69daeb?auto=format&fit=crop&w=800&q=80",
            title = "Specialty Pour-Over & Book Swapping",
            category = "Coffee",
            venue = "Blue Tokai Coffee Roasters, Koregaon Park",
            time = "Saturday · 4:30 PM",
            description = "Let's bring our favorite paperback and discuss recommendations over artisanal aeropress or cascara tonic.",
            participants = listOf("Ananya", "Dev"),
            isJoined = false
        ),
        WeekendPlan(
            id = "plan_2",
            creatorId = "user_2",
            creatorName = "Rohan",
            creatorPhoto = "https://images.unsplash.com/photo-1506794778202-cad84cf45f1d?auto=format&fit=crop&w=800&q=80",
            title = "Sunrise ARAI Hill Hike & Breakfast",
            category = "Hiking",
            venue = "ARAI Hills (Vetal Tekdi) Base Gate",
            time = "Sunday · 6:15 AM",
            description = "Brisk 5km nature walk, catching Pune's golden sunrise mist, followed by hot poha and chai at Wadeshwar.",
            participants = listOf("Rohan", "Pooja", "Vikram"),
            isJoined = false
        ),
        WeekendPlan(
            id = "plan_3",
            creatorId = "user_3",
            creatorName = "Meera",
            creatorPhoto = "https://images.unsplash.com/photo-1529626455594-4ff0802cfb7e?auto=format&fit=crop&w=800&q=80",
            title = "Indie Acoustic Night & Craft Brews",
            category = "Concert",
            venue = "Doolally Taproom, KP",
            time = "Friday · 8:00 PM",
            description = "Local singer-songwriter performing folk & acoustic rock. Looking for good company and mango cider enthusiasts!",
            participants = listOf("Meera", "Kabir"),
            isJoined = true
        ),
        WeekendPlan(
            id = "plan_4",
            creatorId = "user_5",
            creatorName = "Elena",
            creatorPhoto = "https://images.unsplash.com/photo-1544005313-94ddf0286df2?auto=format&fit=crop&w=800&q=80",
            title = "Sunset Mulshi Lake Drive & Picnic",
            category = "Travel",
            venue = "Mulshi Dam Viewpoint",
            time = "Saturday · 3:00 PM",
            description = "Scenic monsoon drive out of the city. Bring snacks, a blanket, and your favorite travel stories.",
            participants = listOf("Elena"),
            isJoined = false
        )
    )

    val curatedDateIdeas = listOf(
        DateIdea(
            title = "Specialty Coffee Crawl & Gallery Walk",
            venueType = "Cafe + Contemporary Art",
            description = "Meet at a cozy independent roaster for artisan pour-overs, then take a stroll through the local art gallery.",
            estimatedBudget = "₹₹ (Moderate)",
            conversationTip = "Ask them about the last piece of art or music that gave them chills."
        ),
        DateIdea(
            title = "Sunset Hilltop Tekdi & Chai",
            venueType = "Outdoor Nature",
            description = "A gentle golden-hour walk up the tekdi with panoramic city views, concluding with authentic clay-cup kulhad chai.",
            estimatedBudget = "₹ (Casual)",
            conversationTip = "Talk about dream travel destinations and funniest weekend misadventures."
        ),
        DateIdea(
            title = "Pottery Workshop or Board Game Cafe",
            venueType = "Interactive & Playful",
            description = "Skip awkward small talk and make something with your hands or team up in a cooperative strategy game.",
            estimatedBudget = "₹₹ (Moderate)",
            conversationTip = "Find out how competitive they get during board games!"
        ),
        DateIdea(
            title = "Rooftop Tapas & Live Jazz",
            venueType = "Evening Romance",
            description = "Ambient string lights, acoustic music, and shared small plates under the open night sky.",
            estimatedBudget = "₹₹₹ (Premium)",
            conversationTip = "Discuss what they'd do if they took a year off from work tomorrow."
        )
    )

    val sampleCrossedPaths = listOf(
        com.example.data.model.CrossedPathEvent(
            id = "cp_1",
            user = initialProfiles[0], // Aanya
            areaDescription = "Around Koregaon Park & North Main Road",
            frequencyText = "Crossed paths 3 times this week",
            mutualPlace = "Blue Tokai Coffee Roasters",
            timeWindowText = "Usually active Friday & Saturday afternoons"
        ),
        com.example.data.model.CrossedPathEvent(
            id = "cp_2",
            user = initialProfiles[1], // Rohan
            areaDescription = "Around ARAI Hills & Pashan Lake",
            frequencyText = "Crossed paths 5 times recently",
            mutualPlace = "ARAI Hills Base & Third Wave Coffee",
            timeWindowText = "Usually active early weekend mornings"
        ),
        com.example.data.model.CrossedPathEvent(
            id = "cp_3",
            user = initialProfiles[2], // Meera
            areaDescription = "Around German Bakery & Osho Garden",
            frequencyText = "Crossed paths 2 times this month",
            mutualPlace = "German Bakery & Prithvi Art Screenings",
            timeWindowText = "Usually active Sunday evenings"
        ),
        com.example.data.model.CrossedPathEvent(
            id = "cp_4",
            user = initialProfiles[4], // Elena
            areaDescription = "Around Zen Cafe & North Main Road",
            frequencyText = "Crossed paths 4 times this month",
            mutualPlace = "Zen Cafe & Osho Teerth Park",
            timeWindowText = "Usually active weekday mornings"
        )
    )
}
