package com.weekend.app

import androidx.test.core.app.ApplicationProvider
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [36])
class GreetingScreenshotTest {

    @Test
    fun `verify app context`() {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        assert(context.getString(com.weekend.app.R.string.app_name) == "Weekend")
    }
}