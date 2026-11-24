package com.lhht.ai_assistant.vision

import org.junit.Assert.*
import org.junit.Test

class VisionLifecycleFenceTest {
    @Test fun delayedDeliveryAfterRevokeCannotSucceedAndIsExactlyOnce() {
        var clock = 100L
        val fence = VisionLifecycleFence({ clock })
        val ticket = fence.Ticket(fence.current(), 200L)
        fence.advance() // pause/consent-off between worker post and main dispatch
        val received = mutableListOf<String?>()
        assertTrue(ticket.deliver(true, null, received::add))
        assertFalse(ticket.deliver(true, null, received::add))
        assertEquals(listOf("cancelled"), received)
    }

    @Test fun slowWriteBeyondDeadlineCannotPublishEvenIfWorkerStartedOnTime() {
        var clock = 100L
        val fence = VisionLifecycleFence({ clock })
        val ticket = fence.Ticket(fence.current(), 112L)
        assertTrue(fence.valid(ticket.token, ticket.deadline))
        clock = 113L // validation/atomic write consumed the remaining budget
        var code: String? = null
        ticket.deliver(true, null) { code = it }
        assertEquals("timeout", code)
    }

    @Test fun queuedCaptureAndLateStartCannotAdoptANewGeneration() {
        var clock = 0L
        val fence = VisionLifecycleFence({ clock })
        val queuedCapture = fence.current()
        val queuedStart = fence.current()
        fence.advance() // close before either worker task executes
        fence.advance() // a subsequent, distinct opening
        assertFalse(fence.valid(queuedCapture))
        assertFalse(fence.valid(queuedStart))
        assertTrue(fence.valid(fence.current()))
        clock = 60_001L
        assertEquals("timeout", fence.reason(fence.current(), 60_000L, true))
    }

    @Test fun postedStateEventIsDroppedWhenGenerationChanges() {
        val fence = VisionLifecycleFence({ 0L })
        val postedReady = fence.current()
        fence.advance() // screen off while ready event waits on main
        assertFalse(fence.valid(postedReady))
    }
}
