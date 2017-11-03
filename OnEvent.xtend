package de.unia.smds.avlab.annotations

import java.lang.annotation.Retention
import java.lang.annotation.Target
import org.eclipse.xtend.lib.macro.AbstractMethodProcessor
import org.eclipse.xtend.lib.macro.Active
import org.eclipse.xtend.lib.macro.TransformationContext
import org.eclipse.xtend.lib.macro.declaration.AnnotationTarget
import org.eclipse.xtend.lib.macro.declaration.MutableClassDeclaration
import org.eclipse.xtend.lib.macro.declaration.MutableMethodDeclaration
import org.eclipse.xtend.lib.macro.declaration.TypeReference
import org.eclipse.xtend.lib.macro.declaration.Visibility
import org.osgi.service.component.annotations.Component
import org.osgi.service.event.Event
import org.osgi.service.event.EventConstants
import org.osgi.service.event.EventHandler

/**
 * Turns the containing class into an OSGi <a href="https://osgi.org/javadoc/r6/cmpn/org/osgi/service/event/EventHandler.html">EventHandler</a> </br>
 * The annotated method should declare the Event it expects </br>
 * There must be exactly ONE parameter! </br>
 * The parameter type must be annotated with @DataTransferObject!
 * @author Thomas Driessen (t.driessen@ds-lab.org)
 */
@Active(OnEventProcessor)
@Target(METHOD)
@Retention(CLASS)
annotation OnEvent {
	String topic = ""
}

class OnEventProcessor extends AbstractMethodProcessor {
	var counter = 0
	var  body = ''
	
	override doTransform(MutableMethodDeclaration method, extension TransformationContext context) {
		
		if(!validAnnotationTarget(method, context))
			return 
		
		val clazz = method.declaringType as MutableClassDeclaration
		val annotation = clazz.annotations.findFirst[annotationTypeDeclaration.qualifiedName.equals(Component.name)]
		val parameter = method.parameters.get(0)
		
		// add new properties to old array
		val property = #['''«EventConstants.EVENT_TOPIC»=«parameter.type.toTopic»'''] + annotation.getStringArrayValue('property')
		val configurationPid = annotation.getStringArrayValue('configurationPid')
		val configurationPolicy = annotation.getEnumValue('configurationPolicy')
		val enabled = annotation.getBooleanValue('enabled')
		val factory = annotation.getStringValue('factory')
		val immediate = annotation.getBooleanValue('immediate')
		val name = annotation.getStringValue('name')
		val properties = annotation.getStringArrayValue('properties')
		val reference = annotation.getAnnotationArrayValue('reference')
		val scope = annotation.getEnumValue('scope')
		val service = annotation.getClassArrayValue('service')
		val servicefactory = annotation.getBooleanValue('servicefactory')
		
		// remove the old annotation
		clazz.removeAnnotation(annotation)
		
		// create new annotation from old one and with new properties
		// check for OSGi default values and only set the new ones if neccessary
		clazz.addAnnotation(newAnnotationReference(Component, [
			if(!(configurationPid.size == 1 && configurationPid.get(0).equals('$'))){
				setStringValue('configurationPid', configurationPid)
			}
			if(!configurationPolicy.simpleName.equals('OPTIONAL')){
				setEnumValue('configurationPolicy', configurationPolicy)
			}
			if(!enabled){
				setBooleanValue('enabled', enabled)
			}
			if(!factory.equals('')){
				setStringValue('factory', factory)
			}
			if(immediate){
				setBooleanValue('immediate', immediate)
			}
			else{
				// if this service was not immediate, but had no interface before it must be made immediate
				// FIXME: if the immediate property has been purposefully set to false, this can not be detected!
				if(clazz.implementedInterfaces.size == 0 && service.size == 0)
					setBooleanValue('immediate', true)
			}
			if(!name.equals('')){
				setStringValue('name', name)
			}
			if(!(properties.size == 0)){
				setStringValue('properties', properties)
			}
			// property is changed anyway, no checks needed
			setStringValue('property', property)
			if(!(reference.size == 0)){
				setAnnotationValue('reference', reference)
			}
			if(!scope.simpleName.equals('DEFAULT')){
				setEnumValue('scope', scope)
			}
			if(!(service.size == 0)){
				// if there have been declared interfaces and EventHandler is not present yet we need to add the EventHandler	
				if(service.findFirst[type.qualifiedName.equals(EventHandler.name)] === null)
					setClassValue('service', #[EventHandler.newTypeReference] + service)
				else
					setClassValue('service', service)
			}
			if(!(servicefactory == false)){
				// this is actually deprecated
				setBooleanValue('servicefactory', servicefactory)
			} 
			// TODO: xmlns?
			
		]))
		
		// add the interface if not already present
		if(clazz.implementedInterfaces.findFirst[type.qualifiedName.equals(EventHandler.name)] === null)
			clazz.implementedInterfaces = clazz.implementedInterfaces + #[EventHandler.newTypeReference]	
		
		// add the handleEvent method if not already present
		var handlerMethod = clazz.declaredMethods.findFirst[simpleName.equals('handleEvent') && parameters.size == 1 && parameters.get(0).type.name.equals(Event.name)]
		if(handlerMethod === null)
			handlerMethod = clazz.addMethod('handleEvent', [
				visibility = Visibility.PUBLIC
				addParameter('event', Event.newTypeReference)
				body = ''''''
			])
			
		// increment our unique variable name counter
		val currentCounter = counter++
		
		// add an additional if statement to the body of handleEvent for our new event
		body = '''
			«body»
			if(event.getTopic().equals("«parameter.type.toTopic»")){
				«parameter.type» dto«currentCounter» = «parameter.type».fromEvent(event);
				«method.simpleName»(dto«currentCounter»);
				return;
			}
			'''
		
		// set the new method body, a little bit ugly, but we cannot just reuse the current method body, because handlerMethod.body returns null -.-
		handlerMethod.body = '''«body»'''
	}
	
	def validAnnotationTarget(MutableMethodDeclaration method, extension TransformationContext context) {
		// check if declaring type is a class (not an interface)
		if(!(method.declaringType instanceof MutableClassDeclaration)){
			method.addError('''@OnEvent may only be used on methods of classes!''')			
			return false 
		}
		// check if declaring type is a @Component
		val clazz = method.declaringType as MutableClassDeclaration
		if(clazz.findAnnotation(Component.newTypeReference.type) === null){
			method.addError('''@OnEvent may only be used within classes that are OSGi components. @Component is missing at «clazz.simpleName»!''')
			return false
		}
		// Make sure there's exactly one parameter
		if(!(method.parameters.size == 1)){
			method.addError('''An @OnEvent method may only have ONE parameter!''')
			return false
		}
		//  Make sure the one parameter is of type @DTO
		if((method.parameters.get(0).type.type as AnnotationTarget).findAnnotation(DataTransferObject.newTypeReference.type) === null){
			method.addError('''The parameter of an @OnEvent method must be a DTO. @DataTransferObject is missing at «method.parameters.get(0).type.simpleName»''')
			return false
		}
		
		return true
	}
	
	private def toTopic(TypeReference type){
		type.name.replace('.', '/')
	}
	
}