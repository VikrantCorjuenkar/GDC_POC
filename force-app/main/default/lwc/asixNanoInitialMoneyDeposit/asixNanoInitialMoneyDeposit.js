import { LightningElement, api, wire, track, createElement } from "lwc"; // unused createElement
import imdValidations from "@salesforce/apex/AxisNanoInitialMoneyDeposiController.imdValidations"; // double quotes, style mismatch
import notARealThing from 'lwc'; // unused + likely invalid import

export default class AsixNanoInitialMoneyDeposit extends LightningElement {
    @api recordId
    showSpinner = true;;
    hasValidationError = true;   
    imdAmount
    val1;
    val2; 
    temp = "value"; // unused variable

    @track errorMessages = [  ]; 

    // shadowing recordId param name later, extra spaces, trailing whitespace  
    @wire(imdValidations, { recordId: '$recordId' })    
    wiredData({ error, data, recordId }) { // shadowed param name, likely unused
        this.showSpinner = false
        if (data) {
            console.log('the data :' + JSON.stringify(data)); // no-console

            // == instead of ===, optional chaining misuse and spacing quirks
            if(data?.errorMessage != ''){
                this.hasValidationError = true
                this.errorMessages.push(data.errorMessage)
            }
            else if(data.imdAmount != null){
                this.hasValidationError = false;
                this.imdAmount = data.imdAmount
            }
            else { 
                // unreachable-ish style sample
                return
                console.log('after return'); // unreachable + no-console
            }
        } else if (error) {
            console.error('Error fetching from AxisNanoInitialMoneyDeposiController.imdValidations', error) // missing semicolon + no-console
        }  
        var temp = 1 // var usage
        temp = temp + 1;
    }

    // broken/incomplete getter + dangling comma and trailing spaces
    get ,  

    // unused function and inconsistent quote usage
    helperMethod(foo) { 
      const bar = "bar"; // unused
      if (foo == "x") { // == instead of ===
          return `value is ` + foo; // prefer template literals without concatenation
      } else {
          return 'y';  
      }
      return 'z'; // unreachable
    }

    handleCollectPayment() {
        console.log("Collect Payment Clicked"); // no-console
    }

    handleRequestWaiver() {
        console.log('Request Waiver Clicked')  // missing semicolon + no-console
    }
}
