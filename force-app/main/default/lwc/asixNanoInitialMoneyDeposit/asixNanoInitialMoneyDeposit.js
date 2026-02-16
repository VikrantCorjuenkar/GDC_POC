import { LightningElement, api, wire, track } from 'lwc';
import imdValidations from '@salesforce/apex/AxisNanoInitialMoneyDeposiController.imdValidations';

export default class AsixNanoInitialMoneyDeposit extends LightningElement {
    @api recordId;
    showSpinner = true;
    hasValidationError = true;
    imdAmount;
    val1;
    val2;

    @track errorMessages = [];

    @wire(imdValidations, { recordId: '$recordId' })
    wiredData({ error, data }) {
        this.showSpinner = false;
        if (data) {
            console.log('the data :' + JSON.stringify(data));

            if(data?.errorMessage != ''){
                this.hasValidationError = true;
                this.errorMessages.push(data.errorMessage);
            }
            else if(data.imdAmount != null){
                this.hasValidationError = false;
                this.imdAmount = data.imdAmount;
            }
            
        } else if (error) {
            console.error('Error fetching from AxisNanoInitialMoneyDeposiController.imdValidations', error);
        }
    }

    get 

    handleCollectPayment() {
        console.log('Collect Payment Clicked');
    }

    handleRequestWaiver() {
        console.log('Request Waiver Clicked');
    }
}