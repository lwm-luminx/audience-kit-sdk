package com.audiencekit

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

class PublisherAdsCopyTest {
    @Test
    fun copyNamesTheAppAndSaysWhoseAdsTheyAre() {
        val body = PublisherAdsCopy.body("Hot Mess")
        assertTrue("Hot Mess takes no cut" in body)
        assertTrue("keep paying writers" in body)
        assertTrue("never shares your data with a publisher's advertisers" in body)
        assertTrue("marked Promoted" in body)
    }

    @Test
    fun matchesTheSwiftWords() {
        assertEquals("Publishers run their own ads", PublisherAdsCopy.TITLE)
        assertEquals("I understand", PublisherAdsCopy.ACCEPT)
        assertEquals("Not now", PublisherAdsCopy.DECLINE)
    }

    @Test
    fun normalizesUserIds() {
        assertEquals("a1b2", PublisherAdsCopy.normalizedUserId(" A1B2 "))
        assertNull(PublisherAdsCopy.normalizedUserId(" "))
        assertNull(PublisherAdsCopy.normalizedUserId(null))
    }
}
