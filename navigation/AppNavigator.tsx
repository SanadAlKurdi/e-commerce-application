import React from 'react';
import { NavigationContainer } from '@react-navigation/native';
import { createNativeStackNavigator } from '@react-navigation/native-stack';

import SplashScreen from '../screens/splashScreen';
import LoginScreen from '../screens/LoginScreen'; // Placeholder, coming in Step 3
import HomeScreen from '../screens/HomeScreen.tsx';
import RegisterScreen from '../screens/RegisterScreen';
import CreateProductScreen from '../screens/CreateProductScreen';
import EditProductScreen from '../screens/EditProductScreen';
import { Product } from '../services/firebaseService.ts';
import CartScreen from '../screens/CartScreen';



export type RootStackParamList = {
  Splash: undefined;
  Login: undefined;
  Home: undefined;
  Register: undefined;
  CreateProductScreen: undefined;
  CartScreen: undefined;
  EditProductScreen: undefined;
  EditProduct: { product: Product };
};

const Stack = createNativeStackNavigator<RootStackParamList>();

export default function AppNavigator() {
  return (
    <NavigationContainer>
      <Stack.Navigator initialRouteName="Splash" screenOptions={{ headerShown: false }}>
        <Stack.Screen name="Splash" component={SplashScreen} />
        <Stack.Screen name="Login" component={LoginScreen} />
        <Stack.Screen name="Home" component={HomeScreen} />
        <Stack.Screen name="Register" component={RegisterScreen} />
        <Stack.Screen name="CreateProductScreen" component={CreateProductScreen} />
        <Stack.Screen name="EditProduct" component={EditProductScreen} />
        <Stack.Screen name="CartScreen" component={CartScreen} />
      </Stack.Navigator>
    </NavigationContainer>
  );
}
