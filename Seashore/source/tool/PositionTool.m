#import "PositionTool.h"
#import "PositionOptions.h"
#import "SeaLayer.h"
#import "SeaDocument.h"
#import "SeaContent.h"
#import "SeaWhiteboard.h"
#import "SeaView.h"
#import "SeaHelpers.h"
#import "SeaTools.h"
#import "SeaSelection.h"
#import "SeaLayerUndo.h"
#import "SeaOperations.h"
#import "SeaRotation.h"
#import "SeaScale.h"

@implementation PositionTool

- (int)toolId
{
	return kPositionTool;
}

- (id)init
{
	if(![super init])
		return NULL;
	
	scale = -1;
	rotation = 0.0;
	rotationDefined = NO;
	
	return self;
}

- (void)mouseDownAt:(IntPoint)where withEvent:(NSEvent *)event
{
	id contents = [document contents];
	SeaLayer * activeLayer = [contents activeLayer];
	IntPoint oldOffsets;
	int whichLayer;
	int function = kMovingLayer;
	
    function = [options toolFunction];
    
	// Record the inital point for dragging
	initialPoint = where;

	// Vary behaviour based on function
	switch (function) {
		case kMovingLayer:
			
			// Determine the absolute where
			where.x += [activeLayer xoff]; where.y += [activeLayer yoff];
			activeLayer = [contents activeLayer];
			
			// Record the inital point for dragging
			initialPoint.x = where.x - [activeLayer xoff];
			initialPoint.y = where.y - [activeLayer yoff];
			
			// If the active layer is linked we have to move all associated layers
			if ([activeLayer linked]) {
			
				// Go through all linked layers allowing a satisfactory undo
				for (whichLayer = 0; whichLayer < [contents layerCount]; whichLayer++) {
					if ([[contents layer:whichLayer] linked]) {
						oldOffsets.x = [[contents layer:whichLayer] xoff]; oldOffsets.y = [[contents layer:whichLayer] yoff];
						[[[document undoManager] prepareWithInvocationTarget:self] undoToOrigin:oldOffsets forLayer:whichLayer];			
					}
				}
				
			}
			else {
				
				// Allow the undo
				oldOffsets.x = [activeLayer xoff]; oldOffsets.y = [activeLayer yoff];
				[[[document undoManager] prepareWithInvocationTarget:self] undoToOrigin:oldOffsets forLayer:[contents activeLayerIndex]];
			
			}
			
		break;
		case kRotatingLayer:
		
			// Start rotating layer
			rotation = 0.0;
			rotationDefined = YES;
			[[document docView] setNeedsDisplay:YES]; 
			
		break;
		case kScalingLayer:
		
			// Start scaling layer
			scale = 1.0;
			[[document docView] setNeedsDisplay:YES];
			
		break;
	}
}

- (void)mouseDraggedTo:(IntPoint)where withEvent:(NSEvent *)event
{
	id contents = [document contents];
	SeaLayer *activeLayer = [contents activeLayer];
	int xoff, yoff, whichLayer;
	int deltax = where.x - initialPoint.x, deltay = where.y - initialPoint.y;
	NSPoint activeCenter = NSMakePoint([activeLayer xoff] + [activeLayer width] / 2, [activeLayer yoff] + [activeLayer height] / 2);
	float original, current;
	
    IntPoint oldOffsets = [activeLayer localRect].origin;
                  
	// Vary behaviour based on function
	switch ([options toolFunction]) {
		case kMovingLayer:
            
			// If the active layer is linked we have to move all associated layers
			if ([activeLayer linked]) {
                IntRect dirty = [activeLayer localRect];
			
				// Move all of the linked layers
				for (whichLayer = 0; whichLayer < [contents layerCount]; whichLayer++) {
                    SeaLayer *layer = [contents layer:whichLayer];
					if ([layer linked]) {
                        dirty = IntSumRects(dirty,[layer localRect]);
						xoff = [layer xoff]; yoff = [layer yoff];
						[layer setOffsets:IntMakePoint(xoff + deltax, yoff + deltay)];
                        dirty = IntSumRects(dirty,[layer localRect]);
                    }
				}
                [[document helpers] layerOffsetsChanged:oldOffsets rect:dirty];
			}
			else {
				// Move the active layer
				xoff = [activeLayer xoff]; yoff = [activeLayer yoff];
				[activeLayer setOffsets:IntMakePoint(xoff + deltax, yoff + deltay)];
                [[document helpers] layerOffsetsChanged:kActiveLayer from:oldOffsets];
			}
		break;
		case kRotatingLayer:
		
			// Continue rotating layer
            rotation = (initialPoint.x - where.x)/(float)[activeLayer width];
            [[document docView] setNeedsDisplay:YES];

		break;
		case kScalingLayer:
	
			// Continue scaling layer
			original = sqrt(sqr(initialPoint.x - activeCenter.x) + sqr(initialPoint.y - activeCenter.y));
			current = sqrt(sqr(where.x - activeCenter.x) + sqr(where.y - activeCenter.y));
			scale = current / original;
            [[document docView] setNeedsDisplay:YES];

		break;
	}
}

- (void)mouseUpAt:(IntPoint)where withEvent:(NSEvent *)event
{
	id layer;
	int deltax;
	int newWidth, newHeight;
    
    id contents = [document contents];
    SeaLayer *activeLayer = [contents activeLayer];
	
	// Determine the delta
	deltax = where.x - initialPoint.x;
    
    int function = [options toolFunction];
    
    // Determine the function
    if ([activeLayer floating] && [options canAnchor] && (where.x < 0 || where.y < 0 || where.x >= [activeLayer width] || where.y >= [activeLayer height])){
        function = kAnchoringLayer;
    }
	
	// Vary behaviour based on function
	switch (function) {
		case kRotatingLayer:
			// Finish rotating layer
			[[seaOperations seaRotation] rotate:rotation * 180.0 / 3.1415 withTrim:YES];
		break;
		case kScalingLayer:
			// Finish scaling layer
			layer = [[document contents] activeLayer];
			newWidth = scale *  [(SeaLayer *)layer width];
			newHeight = scale * [(SeaLayer *)layer height];
			[[seaOperations seaScale] scaleToWidth:newWidth height:newHeight interpolation:NSImageInterpolationHigh index:kActiveLayer];
		break;
        case kAnchoringLayer:
            [contents anchorSelection];
        break;

	}
	
	// Cancel the previewing
	scale = -1;
	rotationDefined = NO;
}

- (float)scale
{
	return scale;
}

- (float)rotation
{
	return rotation;
}

- (BOOL)rotationDefined
{
	return rotationDefined;
}

- (void)undoToOrigin:(IntPoint)origin forLayer:(int)index
{
	IntPoint oldOffsets;
	id layer = [[document contents] layer:index];
	
	oldOffsets.x = [layer xoff]; oldOffsets.y = [layer yoff];
	[[[document undoManager] prepareWithInvocationTarget:self] undoToOrigin:oldOffsets forLayer:index];
	[layer setOffsets:origin];
	[[document helpers] layerOffsetsChanged:index from:oldOffsets];
}

- (AbstractOptions*)getOptions
{
    return options;
}
- (void)setOptions:(AbstractOptions*)newoptions
{
    options = (PositionOptions*)newoptions;
}


@end
