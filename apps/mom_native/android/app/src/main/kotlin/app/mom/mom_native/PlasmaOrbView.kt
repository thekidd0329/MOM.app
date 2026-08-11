package app.mom.mom_native

import android.content.Context
import android.graphics.BlurMaskFilter
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.util.AttributeSet
import android.view.View
import java.util.Random
import kotlin.math.cos
import kotlin.math.sin

class PlasmaOrbView @JvmOverloads constructor(
    context: Context, attrs: AttributeSet? = null, defStyleAttr: Int = 0
) : View(context, attrs, defStyleAttr) {

    private val random = Random()
    
    // Paint for the thick purple outer glow
    private val glowPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.parseColor("#A020F0") // Purple
        style = Paint.Style.STROKE
        strokeCap = Paint.Cap.ROUND
        // Adds a soft blur effect for the plasma glow
        maskFilter = BlurMaskFilter(15f, BlurMaskFilter.Blur.NORMAL)
    }

    // Paint for the thin white hot electrical core
    private val corePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.WHITE
        style = Paint.Style.STROKE
        strokeCap = Paint.Cap.ROUND
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)

        val centerX = width / 2f
        val centerY = height / 2f
        val radius = (Math.min(width, height) / 2f) * 0.8f // Orb size

        // 1. DRAW THE CENTRAL GLOWING CORE
        canvas.drawCircle(centerX, centerY, 20f, corePaint)

        // 2. GENERATE MAIN LIGHTNING FILAMENTS
        val numberOfBranches = 8
        for (i in 0 until numberOfBranches) {
            // Distribute branches evenly around the 360-degree circle
            val targetAngle = (i * (360f / numberOfBranches)) + random.nextFloat() * 15f
            val angleRad = Math.toRadians(targetAngle.toDouble())
            
            // Calculate where the lightning path should ideally end on the border
            val targetX = centerX + radius * cos(angleRad).toFloat()
            val targetY = centerY + radius * sin(angleRad).toFloat()

            // Draw the lightning path
            drawLightningBolt(canvas, centerX, centerY, targetX, targetY)
        }

        // 3. GENERATE LITTLE EDGE ARCS
        val edgeArcsCount = 4
        for (i in 0 until edgeArcsCount) {
            drawEdgeArc(canvas, centerX, centerY, radius)
        }

        // 4. THE ANIMATION LOOP
        // Tells Android to instantly redraw the screen, creating constant fluid motion
        postInvalidateOnAnimation()
    }

    // Function to calculate and draw a single zig-zag lightning branch
    private fun drawLightningBolt(canvas: Canvas, startX: Float, startY: Float, endX: Float, endY: Float) {
        val path = Path()
        path.moveTo(startX, startY)

        val segments = 6
        var currentX = startX
        var currentY = startY

        // Randomly vary the line thickness per frame to simulate a power surge
        val currentThickness = 3f + random.nextFloat() * 5f 
        glowPaint.strokeWidth = currentThickness + 8f // Extra wide for glow
        corePaint.strokeWidth = currentThickness * 0.4f // Thin white interior

        for (i in 1..segments) {
            val fraction = i.toFloat() / segments
            
            // Linear progression point from center to edge
            val idealX = startX + (endX - startX) * fraction
            val idealY = startY + (endY - startY) * fraction

            // Add chaos! Shift the point left/right/up/down randomly
            val jitter = 25f 
            currentX = idealX + (random.nextFloat() - 0.5f) * jitter
            currentY = idealY + (random.nextFloat() - 0.5f) * jitter

            if (i == segments) {
                path.lineTo(endX, endY) // Snap perfectly to the outer rim
            } else {
                path.lineTo(currentX, currentY)
            }
        }

        // Draw the purple glow background, then stack the white electrical core directly on top
        canvas.drawPath(path, glowPaint)
        canvas.drawPath(path, corePaint)
    }

    // Function to draw small arcs hugging the outer rim
    private fun drawEdgeArc(canvas: Canvas, centerX: Float, centerY: Float, radius: Float) {
        val path = Path()
        
        // Pick a random starting angle on the rim
        val startAngle = random.nextFloat() * 360f
        // Make the arc short (jumping 20 to 40 degrees along the border)
        val endAngle = startAngle + 20f + random.nextFloat() * 20f

        val startRad = Math.toRadians(startAngle.toDouble())
        val endRad = Math.toRadians(endAngle.toDouble())

        val startX = centerX + radius * cos(startRad).toFloat()
        val startY = centerY + radius * sin(startRad).toFloat()
        val endX = centerX + radius * cos(endRad).toFloat()
        val endY = centerY + radius * sin(endRad).toFloat()

        path.moveTo(startX, startY)

        // Middle point of the arc pushed slightly outward past the radius
        val midAngle = (startAngle + endAngle) / 2f
        val midRad = Math.toRadians(midAngle.toDouble())
        val burstOutward = radius + (5f + random.nextFloat() * 15f) // Leaks over edge
        val midX = centerX + burstOutward * cos(midRad).toFloat()
        val midY = centerY + burstOutward * sin(midRad).toFloat()

        path.lineTo(midX, midY)
        path.lineTo(endX, endY)

        // Set thin settings for edge sparks
        glowPaint.strokeWidth = 6f
        corePaint.strokeWidth = 2f

        canvas.drawPath(path, glowPaint)
        canvas.drawPath(path, corePaint)
    }
}
