package de.unia.smds.avlab.annotations

import java.lang.annotation.Retention
import java.lang.annotation.Target
import java.util.ArrayList
import java.util.Collection
import java.util.Dictionary
import java.util.Hashtable
import java.util.List
import java.util.Map
import org.eclipse.xtend.lib.macro.AbstractClassProcessor
import org.eclipse.xtend.lib.macro.Active
import org.eclipse.xtend.lib.macro.TransformationContext
import org.eclipse.xtend.lib.macro.declaration.AnnotationTarget
import org.eclipse.xtend.lib.macro.declaration.ClassDeclaration
import org.eclipse.xtend.lib.macro.declaration.Element
import org.eclipse.xtend.lib.macro.declaration.MutableClassDeclaration
import org.eclipse.xtend.lib.macro.declaration.MutableFieldDeclaration
import org.eclipse.xtend.lib.macro.declaration.TypeReference
import org.eclipse.xtend.lib.macro.declaration.Visibility
import org.osgi.dto.DTO
import org.osgi.service.event.Event

/**
 * Turns any class into a <a href="https://osgi.org/javadoc/r6/core/org/osgi/dto/DTO.html">DTO</a>, that complies to the following rules: 
 *  <ul>
 *	  <li><strong>public</strong> – Only public classes with public members work as DTO.</li>
 *	  <li><strong>static</strong> – Fields must <strong>not</strong> be static but inner classes must be static.</li>
 *	  <li><strong>no-arg constructor</strong> – To allow instantiation before setting the fields</li>
 *	  <li><strong>extend</strong> – DTOs can extend another DTO</li>
 *	  <li><strong>no generics</strong> – DTOs should never have a generic signature, nor extend a class that has a generic signature because this makes serialization really hard.</li>
 *	</ul>
 * Additionally this annotations adds a
 * <ul>
 * 	<li><code>public Dictionary toDictionary()</code> method</li>
 *  <li><code>public static "DTOType" fromDictionary(Dictionary<String, Object> properties)</code> method</li>
 *  <li><code>public Event toEvent()</code> method</li>
 *  <li><code>public static "DTOType" fromEvent(Event event)</code> method</li>
 * </ul>
 * 
 * @see <a href="http://enroute.osgi.org/appnotes/dtos.html">OSGi enRoute - DTOs</a>
 * 
 * @author Thomas Driessen (t.driessen@ds-lab.org)
 */
@Active(OSGiDTOProcessor)
@Target(TYPE)
@Retention(CLASS)
annotation DataTransferObject {
	String topic = ''
}

class OSGiDTOProcessor extends AbstractClassProcessor {
	
	override doTransform(MutableClassDeclaration clazz, extension TransformationContext context) {
		if(!validAnnotationTarget(clazz, context)){
			return
		}
		
		val tableRef = Hashtable.newTypeReference(String.newTypeReference, Object.newTypeReference)
		val dicRef = Dictionary.newTypeReference(String.newTypeReference, Object.newTypeReference)
		// add a toDicitionary method that returns all fields of this DTO in form of a Dictionary
		clazz.addMethod('toDictionary', [
			visibility = Visibility.PUBLIC
			returnType = dicRef
			body = '''
				«tableRef» properties = new «tableRef»();
				«FOR field : clazz.declaredFields»
					«IF field.type.isDTO(context)»
						properties.put("«field.simpleName»", «field.simpleName».toDictionary());				
					«ELSE»
						properties.put("«field.simpleName»", «field.simpleName»);
					«ENDIF»
				«ENDFOR»
				return properties;
			'''
		])
		
		// add a fromDicitionary method that returns a "DTOType" created from a given Dictionary
		clazz.addMethod('fromDictionary', [
			visibility = Visibility.PUBLIC
			returnType = clazz.newSelfTypeReference
			static = true
			addParameter('properties', dicRef)
			body ='''
				«clazz.newSelfTypeReference» dto = new «clazz.newSelfTypeReference»();
				«FOR field : clazz.declaredFields»
					«IF field.type.isDTO(context)»
						dto.«field.simpleName» = «field.type».fromDictionary((«dicRef»)properties.get("«field.simpleName»"));
					«ELSE»
						dto.«field.simpleName» =  («field.type») properties.get("«field.simpleName»");
					«ENDIF»
				«ENDFOR»
				return dto;
			'''
		])
		
		clazz.addMethod('toEvent', [
			returnType = Event.newTypeReference
			visibility = Visibility.PUBLIC
			body = '''
				return new «Event.newTypeReference»("«clazz.newSelfTypeReference.toTopic»", toDictionary());
			'''
			// TODO: regard the "topic" parameter in DTO annotation
			docComment = '''
				Creates a <a href="https://osgi.org/javadoc/r6/cmpn/org/osgi/service/event/Event.html">Event</a> from this Object. </br>
				All fields are saved in a <code>Dictionary<String, Object></code>, </br>
				where the name of the field is used as key and the value of the field as value.</br>
				The topic of this event is:</br>
				«clazz.newSelfTypeReference.toTopic»
			'''
		])
		
		clazz.addMethod('fromEvent', [
			returnType = clazz.newSelfTypeReference
			visibility = Visibility.PUBLIC
			addParameter('event', Event.newTypeReference)
			static = true
			body = '''
				«clazz.newSelfTypeReference» dto = new «clazz.newSelfTypeReference»();
				«FOR field : clazz.declaredFields»
					«IF field.type.isDTO(context)»
						dto.«field.simpleName» = «field.type».fromDictionary((«dicRef») event.getProperty("«field.simpleName»"));
					«ELSE»
						dto.«field.simpleName» =  («field.type») event.getProperty("«field.simpleName»");
					«ENDIF»
				«ENDFOR»
				return dto;
			'''
			docComment = '''
				Creates a new instance of type «clazz.simpleName» from the given <a href="https://osgi.org/javadoc/r6/cmpn/org/osgi/service/event/Event.html">Event</a>. </br>
				All fields are filled according to the values provided by the properties of <code>event</code></br>
				where the name of the field is used as key </br>
				
				@param event The <a href="https://osgi.org/javadoc/r6/cmpn/org/osgi/service/event/Event.html">Event</a> used to construct a «clazz.simpleName» from
				@return A «clazz.simpleName»
			'''
		])
		
		// if this class not already extends something, then let it extend DTO
		if(clazz.extendedClass.type.qualifiedName.equals(Object.name))
			clazz.extendedClass = DTO.newTypeReference
		
	}
	
	/**
	 *  <ul>
	 *	  <li><strong>public</strong> – Only public classes with public members work as DTO.</li>
	 *	  <li><strong>static</strong> – Fields must <strong>not</strong> be static but inner classes must be static.</li>
	 *	  <li><strong>no-arg constructor</strong> – To allow instantiation before setting the fields</li>
	 *	  <li><strong>extend</strong> – DTOs can extend another DTO</li>
	 *	  <li><strong>no generics</strong> – DTOs should never have a generic signature, nor extend a class that has a generic signature because this makes serialization really hard.</li>
	 *	</ul>
	 * Grammar: </br>
	 * T          ::= dto | primitives | String | array | map | list </br>
	 * primitives ::= byte | char | short | int | long | float | double </br>
	 * list	      ::= ? extends Collection<T> </br>
	 * map        ::= ? extends Map<String,T> </br>
	 * dto        ::= <> </br>
 	 */
	def validAnnotationTarget(MutableClassDeclaration clazz, extension TransformationContext context) {
		// check if class members comply to the rules of a DTO (primitives, Collections, Maps, other DTOs, no circles)
		if(clazz.visibility != Visibility.PUBLIC){
			clazz.addError('''A DTO must be a public class!''')
			return false
		}
		
		if(clazz.typeParameters.size != 0){
			clazz.addError('''A DTO should never have a generic signature!''')
			return false
		}
		
		// TODO: check all if this class extends another class. If so, check if there is DTO class at the top
		
		val staticField = clazz.declaredFields.findFirst[static]
		if(staticField !== null){
			staticField.addError('''A DTO may not contain static fields!''')
			return false
		}
		
		val nonPublicField = clazz.declaredFields.findFirst[!(visibility == Visibility.PUBLIC)]
		if(nonPublicField !== null){
			nonPublicField.addError('''A DTO may not contain non-public fields!''')
			return false
		}
		
		val noArgsConstructor = clazz.declaredConstructors.findFirst[parameters.size == 0]
		if(clazz.declaredConstructors.size > 0 && noArgsConstructor === null){
			clazz.addError('''A DTO must define a no-args constructor!''')
			return false
		}
		// check if only allowed types
		val invalidFieldType = clazz.declaredFields.findFirst[!type.isAllowedDTOType(context, it)]
		if(invalidFieldType !== null){
			return false
		}
		
		// check for circles
		if((clazz.primarySourceElement as ClassDeclaration).containsCircles(new ArrayList, context))
			return false
		
		return true
	}
	
	private def sourceClassDeclaration(Element element, extension TransformationContext context){
		var sourceRef = element.primarySourceElement as TypeReference
		return sourceRef.type as ClassDeclaration
	}
	
	private def boolean containsCircles(ClassDeclaration clazz, List<String> path, extension TransformationContext context){
		if(path.contains(clazz.qualifiedName))
			return true
		path.add(clazz.qualifiedName)
		// check all children
		
		for (field : clazz.declaredFields) {
			if(field.type.isDTO(context)){
				if(field.type.sourceClassDeclaration(context).containsCircles(path, context)){
					field.addError('Circular references are not allowed!')					
					return true
				}
			}
			
			if(Map.newTypeReference.isAssignableFrom(field.type) || Collection.newTypeReference.isAssignableFrom(field.type)){
				for(genericType : field.type.actualTypeArguments.filter[isDTO(context)].map[sourceClassDeclaration(context)]){
					if(genericType.containsCircles(path, context)){
						field.addError('Circular references are not allowed!')					
						return true
					}
				}
			}
			
			if(field.type.array){
				if(field.type.arrayComponentType.isDTO(context)){
					if(field.type.arrayComponentType.sourceClassDeclaration(context).containsCircles(path, context)){
						field.addError('Circular references are not allowed!')					
						return true
					}
				}
			}
		}
		
		// no circle has been detected, remove this classname from the path
		path.remove(clazz.qualifiedName)
		return false
	}
	
	private def boolean isAllowedDTOType(TypeReference type, extension TransformationContext context, MutableFieldDeclaration field){
		if(type === null){
			field.addError('''Type may not be null!''')
			return false
		}
			
		if(type.primitive)
			return true
		
		if(type.wrapper)
			return true
		
		if(type.array){
			return type.arrayComponentType.isAllowedDTOType(context, field)
		}
		
		if(type.type.qualifiedName.equals(String.name))
			return true
			
		if(Map.newTypeReference.isAssignableFrom(type)){
			// check type arguments of Map for being allowedDTOTypes
			for(genericType : type.actualTypeArguments){
				if(!genericType.isAllowedDTOType(context, field)){
					return false
				}
			}
			return true
		}
		
		if(Collection.newTypeReference.isAssignableFrom(type)){
			if(type.actualTypeArguments.size == 0)
				return true
			// check type argument of Collection for being allowedDTOTypes
			return type.actualTypeArguments.get(0).isAllowedDTOType(context, field)
		}
		
		if(type.isDTO(context))
			return true
		
		field.addError('''Type «type» is not allowed as DTO!''')	
		return false
	}
	
	private def toTopic(TypeReference type){
		type.name.replace('.', '/')
	}
	
	private def isDTO(TypeReference type, extension TransformationContext context){
		if(type !== null && context !== null && type.type instanceof AnnotationTarget){
			var annotationTarget = type.type as AnnotationTarget
			var annotationType = DataTransferObject.newTypeReference.type
			var annotation = annotationTarget.findAnnotation(annotationType)
			return annotation !== null
		} 
		else
			return false
	}
	
}